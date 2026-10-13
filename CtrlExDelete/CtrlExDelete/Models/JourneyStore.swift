import SwiftUI

// The user's journey after the check-in, shared by the room, activities,
// reflection and scrapbook screens. Everything here comes from the backend,
// so it is the same after the app restarts.

/// The activity in progress: chosen with "I'll try this", finished by its
/// reflection or set aside with "Change activity". There is at most one.
struct SelectedActivity {
    let selectionId: Int        // the activity_selections row, sent with the reflection
    let activity: Activity
    let startedOn: String       // e.g. "Oct 13"

    init(_ dto: SelectedActivityDTO) {
        selectionId = dto.selectionId
        activity = Activity(activity: dto.activity, recommendationId: dto.recommendationId)
        startedOn = Self.dayText(dto.selectedAt)
    }

    /// "2026-10-13T04:37:02.118204Z" -> "Oct 13" in the user's time zone.
    /// The fractional seconds are dropped first: the API sends six digits,
    /// which ISO8601DateFormatter doesn't accept.
    private static func dayText(_ timestamp: String) -> String {
        let trimmed = timestamp.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let date = ISO8601DateFormatter().date(from: trimmed)
        return date?.formatted(.dateTime.month(.abbreviated).day()) ?? ""
    }
}

/// One card in the scrapbook's "Recent Memories".
struct ScrapbookMemory: Identifiable {
    let id: Int
    let title: String
    let reflection: String?   // shown in quotes; nil if the user wrote nothing
    let date: String          // e.g. "September 4"
    let tint: Color           // background behind the photo
    let imageURL: URL?        // temporary S3 link; nil without a photo

    init(_ dto: ReflectionDTO) {
        id = dto.id
        title = dto.activity?.title ?? "Today\u{2019}s activity"
        reflection = dto.note ?? dto.noticed
        date = LocalDate.format(dto.localDate, .dateTime.month(.wide).day())
        tint = dto.activity.map { Activity.palette(for: $0.category).background } ?? CEDColor.secondary
        imageURL = dto.imageUrl
    }
}

/// One step in the scrapbook's "Your story so far".
struct JourneyMilestone: Identifiable {
    let label: String
    let date: String          // e.g. "Aug 18", or "Upcoming"
    let isDone: Bool
    var id: String { label }
}

@Observable
final class JourneyStore {
    private(set) var selectedActivity: SelectedActivity?
    /// Newest first.
    private(set) var memories: [ScrapbookMemory] = []
    private(set) var summary: ProgressSummaryDTO?
    private(set) var hasLoaded = false
    private(set) var loadError: String?

    /// "Day N" in the headers: day 1 is the day of the first check-in.
    var dayNumber: Int {
        guard let start = summary?.journeyStartedOn.flatMap({ LocalDate.date(from: $0) }) else { return 1 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        return max(1, days + 1)
    }

    var milestones: [JourneyMilestone] {
        (summary?.milestones ?? []).map { milestone in
            JourneyMilestone(
                label: milestone.label,
                date: milestone.reachedOn.map { LocalDate.format($0, .dateTime.month(.abbreviated).day()) } ?? "Upcoming",
                isDone: milestone.reachedOn != nil
            )
        }
    }

    // MARK: Loading

    /// Reloads the current choice, the memories and the progress counts.
    func refresh() async {
        do {
            // One after another: `async let` crashes the Swift runtime here
            // (swift_task_dealloc) with the project's MainActor default isolation.
            let currentSelection = try await APIClient.shared.currentSelection()
            let savedReflections = try await APIClient.shared.reflections()
            let progress = try await APIClient.shared.progressSummary()

            selectedActivity = currentSelection.map(SelectedActivity.init)
            memories = savedReflections.map(ScrapbookMemory.init)
            self.summary = progress
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        hasLoaded = true
    }

    // MARK: Choosing, changing and completing an activity

    /// "I'll try this": starts the activity (in progress). Choosing is not
    /// completing; that happens when its reflection is saved.
    func select(_ activity: Activity) async throws {
        do {
            _ = try await APIClient.shared.selectRecommendation(id: activity.recommendationId)
        } catch APIError.server(status: 409, let detail) {
            // Another activity is already in progress (maybe from a request
            // this screen didn't know about): show it instead.
            await refresh()
            throw APIError.server(status: 409, detail: detail)
        }
        selectedActivity = try await APIClient.shared.currentSelection().map(SelectedActivity.init)
        summary = try? await APIClient.shared.progressSummary()
    }

    /// "Change activity": sets the activity in progress aside. It doesn't
    /// count as completed, and saved memories stay as they are.
    func abandonCurrentActivity() async throws {
        guard let current = selectedActivity else { return }
        _ = try await APIClient.shared.abandonSelection(id: current.selectionId)
        selectedActivity = nil
        await refresh()
    }

    /// "Save for later" on or off. Never selects the activity.
    func setSaved(_ isSaved: Bool, activityId: Int) async throws {
        try await APIClient.shared.setSaved(activityId: activityId, isSaved)
    }

    /// Deletes a memory and its photo. The activity still counts as completed.
    func deleteMemory(id: Int) async throws {
        try await APIClient.shared.deleteReflection(id: id)
        memories.removeAll { $0.id == id }
        await refresh()
    }

    /// Uploads one photo to S3 and returns its id for `saveReflection`.
    func uploadPhoto(jpeg: Data) async throws -> Int {
        try await APIClient.shared.uploadScrapbookPhoto(jpeg: jpeg).id
    }

    /// "Add to my scrapbook": saves the memory, which completes the activity in progress.
    func saveReflection(_ request: ReflectionRequest) async throws {
        let saved = try await APIClient.shared.saveReflection(request)
        if !memories.contains(where: { $0.id == saved.id }) {
            memories.insert(ScrapbookMemory(saved), at: 0)
        }
        if selectedActivity?.selectionId == saved.activitySelectionId {
            selectedActivity = nil
        }
        await refresh()
    }
}

// MARK: - Dates from the API

/// The API sends calendar days as "YYYY-MM-DD" in the user's own time zone.
enum LocalDate {
    static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static func format(_ text: String, _ style: Date.FormatStyle) -> String {
        date(from: text)?.formatted(style) ?? text
    }
}
