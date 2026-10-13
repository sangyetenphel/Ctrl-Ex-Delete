import SwiftUI

// Local, temporary data shared by the screens after the check-in.
// Nothing here is sent to the backend; it resets when the app closes.

/// One card in the scrapbook's "Recent Memories".
struct ScrapbookMemory: Identifiable {
    let id = UUID()
    let title: String
    let reflection: String?   // shown in quotes; nil if the user wrote nothing
    let date: String          // e.g. "September 4"
    let tint: Color           // background behind the photo placeholder
}

@Observable
final class JourneyStore {
    /// The activity chosen with "I'll try this", kept for the reflection screen.
    var selectedActivity: Activity?

    /// Newest first. Starts with the two sample memories from the prototype.
    private(set) var memories: [ScrapbookMemory] = [
        ScrapbookMemory(title: "Evening Walk", reflection: "My mind felt calmer", date: "September 4", tint: Color(hex: 0xFDE8D8)),
        ScrapbookMemory(title: "Solo Coffee Date", reflection: "I enjoyed time alone", date: "August 26", tint: Color(hex: 0xE8F0E0)),
    ]

    /// Adds a memory from the reflection screen for the selected activity.
    func addMemory(note: String, on date: Date = .now) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let memory = ScrapbookMemory(
            title: selectedActivity?.title ?? "Today\u{2019}s activity",
            reflection: trimmed.isEmpty ? nil : trimmed,
            date: date.formatted(.dateTime.month(.wide).day()),
            tint: selectedActivity?.background ?? CEDColor.secondary
        )
        memories.insert(memory, at: 0)
    }
}

#if DEBUG
// MARK: - Testing without the backend

extension JourneyStore {
    /// Launch argument `-CEDSampleActivity YES` pretends the first prototype
    /// activity was chosen, so reflection and scrapbook can be tested offline.
    static func debugStore() -> JourneyStore {
        let store = JourneyStore()
        if UserDefaults.standard.bool(forKey: "CEDSampleActivity") {
            store.selectedActivity = .debugSample
        }
        return store
    }
}

extension Activity {
    /// The prototype's first card, shaped like a backend recommendation.
    static let debugSample = Activity(recommendation: RecommendationDTO(
        id: 0,
        position: 1,
        activity: ActivityDTO(
            id: 0,
            slug: "sit-in-sunlight",
            title: "Sit somewhere with sunlight.",
            category: "mindfulness_rest",
            categoryLabel: "Gentle Reset",
            durationMinutes: 10,
            instructions: "No productivity needed. Notice three things you can see and take five slow breaths.",
            whyItFits: "Your energy is low and the urge to reach out is moderate. This activity gives your nervous system a soft reset."
        ),
        selectedAt: nil
    ))
}
#endif
