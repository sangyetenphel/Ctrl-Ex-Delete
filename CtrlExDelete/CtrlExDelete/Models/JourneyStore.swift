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
    let reflection: String?   // "What did you notice?", shown in quotes; nil if left empty
    let date: String          // e.g. "September 4"
    let tint: Color           // background behind the photo
    let imageURL: URL?        // temporary S3 link; nil without a photo

    init(_ dto: ReflectionDTO) {
        id = dto.id
        title = dto.activity?.title ?? "Today\u{2019}s activity"
        reflection = dto.note
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
    /// Ced's message in the room, for the local day it belongs to (kept on the
    /// phone). Only today's is ever shown; see `roomMessageText(today:)`.
    private(set) var roomMessage: RoomMessageRecord? = RoomMessageCache.load()
    private var isLoadingRoomMessage = false

    /// The room's books: one per completed activity, earliest first (≤ 32).
    /// Never emptied by a failed request; kept on the phone between launches.
    private(set) var books: [ShelfBookDTO] = []
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    /// When the progress on screen was last confirmed by the backend, if it
    /// came from the on-device copy instead (the backend couldn't be reached).
    /// nil once fresh data has loaded.
    private(set) var cachedAt: Date?

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
    /// Errors are kept in `loadError` for the screens to show.
    func refresh() async {
        do {
            try await reloadStory()
        } catch {
            loadError = error.localizedDescription
        }
        hasLoaded = true
    }

    /// Same as `refresh()`, but throws, so a caller can retry it. Nothing is
    /// replaced unless all three requests succeed.
    func reloadStory() async throws {
        // One after another: `async let` crashes the Swift runtime here
        // (swift_task_dealloc) with the project's MainActor default isolation.
        let currentSelection = try await APIClient.shared.currentSelection()
        let savedReflections = try await APIClient.shared.reflections()
        let progress = try await APIClient.shared.progressSummary()
        // The shelf is extra: if it can't load, the books already shown stay.
        if let shelf = try? await APIClient.shared.bookshelf() {
            books = shelf.books
        }

        selectedActivity = currentSelection.map(SelectedActivity.init)
        memories = savedReflections.map(ScrapbookMemory.init)
        self.summary = progress
        loadError = nil
        hasLoaded = true
        cachedAt = nil
        JourneyCache.save(selection: currentSelection, reflections: savedReflections, summary: progress, books: books)
    }

    // MARK: Startup

    /// Startup and returning to the app: asks the backend whether the user
    /// has checked in on `today` and reloads their progress. The backend is
    /// the source of truth; if it can't be reached this throws, and nothing
    /// is decided from the error (no new user, no extra check-in).
    func restoreSession(today: String) async throws -> CheckInStatusDTO {
        let status = try await APIClient.shared.checkInStatus(localDate: today)
        applyRoomMessage(status.roomMessage, checkInId: status.checkIn?.id, localDate: status.localDate)
        try await reloadStory()
        return status
    }

    // MARK: Ced's room message

    /// What Ced says in the room today. Never another day's message: until
    /// today's is known (loading, or no connection and nothing saved for
    /// today) it's a neutral line.
    func roomMessageText(today: String) -> String {
        guard let roomMessage, roomMessage.localDate == today else { return RoomMessageRecord.neutralText }
        return roomMessage.text
    }

    /// Keeps a message from the backend (after checking in, or today's status).
    func applyRoomMessage(_ message: RoomMessageDTO?, checkInId: Int?, localDate: String) {
        guard let message else { return }
        let record = RoomMessageRecord(text: message.text, pattern: message.pattern, checkInId: checkInId,
                                       localDate: localDate, installationID: try? InstallationID.current())
        // A personal message for today is never replaced by a "let's check in" one.
        if let current = roomMessage, current.localDate == localDate, current.isPersonal, !record.isPersonal { return }
        roomMessage = record
        RoomMessageCache.save(record)
    }

    /// Fetches today's message when none is known for today. A failure keeps
    /// whatever belongs to today and changes nothing else.
    func loadRoomMessage(today: String) async {
        guard roomMessage?.localDate != today, !isLoadingRoomMessage else { return }
        isLoadingRoomMessage = true
        defer { isLoadingRoomMessage = false }
        if let status = try? await APIClient.shared.checkInStatus(localDate: today) {
            applyRoomMessage(status.roomMessage, checkInId: status.checkIn?.id, localDate: status.localDate)
        }
    }

    /// Shows the progress saved on this device after the last successful load,
    /// while the backend can't be reached. Returns false if there is none.
    @discardableResult
    func showCachedProgress() -> Bool {
        guard !hasLoaded || cachedAt != nil, let cache = JourneyCache.load() else { return false }
        selectedActivity = cache.selection.map(SelectedActivity.init)
        memories = cache.reflections.map(ScrapbookMemory.init)
        summary = cache.summary
        if books.isEmpty { books = cache.books ?? [] }
        cachedAt = cache.savedAt
        hasLoaded = true
        return true
    }

    // MARK: Choosing, changing and completing an activity

    /// "I'll try this": starts the activity (in progress). Choosing is not
    /// completing; that happens when its reflection is saved.
    func select(_ activity: Activity) async throws {
        do {
            _ = try await APIClient.shared.selectRecommendation(id: activity.recommendationId)
        } catch APIError.server(let status, let detail) where status == 409 || status == 404 {
            // 409: another activity is already in progress (maybe from a
            // request this screen didn't know about): show it instead.
            // 404: the card is gone (e.g. the test data was reset): reload,
            // so nothing stale stays on screen.
            await refresh()
            throw APIError.server(status: status, detail: detail)
        }
        selectedActivity = try await APIClient.shared.currentSelection().map(SelectedActivity.init)
        // The day count can catch up in the background; the reflection
        // screen shouldn't wait for it.
        Task { if let progress = try? await APIClient.shared.progressSummary() { summary = progress } }
    }

    /// "Change activity": sets the activity in progress aside. It doesn't
    /// count as completed, and saved memories stay as they are.
    func abandonCurrentActivity() async throws {
        guard let current = selectedActivity else { return }
        do {
            _ = try await APIClient.shared.abandonSelection(id: current.selectionId)
        } catch APIError.server(status: 404, _) {
            // Already gone on the server, which is what was asked for.
        }
        selectedActivity = nil
        await refresh()
    }

    /// "Save for later" on or off. Never selects the activity.
    func setSaved(_ isSaved: Bool, activityId: Int) async throws {
        try await APIClient.shared.setSaved(activityId: activityId, isSaved)
    }

    /// Deletes a memory and its photo. The activity still counts as completed.
    func deleteMemory(id: Int) async throws {
        do {
            try await APIClient.shared.deleteReflection(id: id)
        } catch APIError.server(status: 404, _) {
            // Already gone on the server: just drop the stale card.
        }
        memories.removeAll { $0.id == id }
        await refresh()
    }

    /// Uploads one photo to S3 and returns its id for `saveReflection`.
    func uploadPhoto(jpeg: Data) async throws -> Int {
        try await APIClient.shared.uploadScrapbookPhoto(jpeg: jpeg).id
    }

    /// "Add to my scrapbook": saves the memory, which completes the activity
    /// in progress. Only this request; call `reloadStory()` afterwards, so a
    /// failed refresh can be retried without saving again. (Saving the same
    /// selection twice is harmless anyway: the backend returns the first memory.)
    @discardableResult
    func saveReflection(_ request: ReflectionRequest) async throws -> ReflectionDTO {
        let saved: ReflectionDTO
        do {
            saved = try await APIClient.shared.saveReflection(request)
        } catch APIError.server(status: 404, let detail) {
            // The activity in progress or the photo no longer exists (e.g. the
            // test data was reset): reload, so the screens stop showing it.
            await refresh()
            throw APIError.server(status: 404, detail: detail)
        }
        if !memories.contains(where: { $0.id == saved.id }) {
            memories.insert(ScrapbookMemory(saved), at: 0)
        }
        if selectedActivity?.selectionId == saved.activitySelectionId {
            selectedActivity = nil
        }
        return saved
    }
}

// MARK: - Dates from the API

/// The API sends calendar days as "YYYY-MM-DD" in the user's own time zone.
///
/// Time zone policy: "today" is the phone's current calendar day in its
/// current time zone (midnight to midnight), never a rolling 24 hours and
/// never UTC. The app sends that day with check-ins, reflections and
/// insights; the backend stores it as is and allows one check-in per day.
enum LocalDate {
    /// "YYYY-MM-DD" for `date` in the phone's current time zone.
    static func text(for date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

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
