import SwiftUI

// Check-in options, activity cards, and the screen state that goes with them.
// The raw values of Emotion, EnergyLevel and HardestArea are the exact values
// the API expects (see docs/api.md), so don't change them without the backend.

// MARK: - Check-in options

enum Emotion: String, CaseIterable, Identifiable, Codable {
    case heavy
    case gettingThrough = "getting_through"
    case missingThem = "missing_them"
    case hopeful

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heavy: "Heavy"
        case .gettingThrough: "Getting through"
        case .missingThem: "Missing them"
        case .hopeful: "Hopeful"
        }
    }

    var subtitle: String {
        switch self {
        case .heavy: "It feels overwhelming"
        case .gettingThrough: "One step at a time"
        case .missingThem: "Thoughts keep returning"
        case .hopeful: "The weight feels lighter"
        }
    }

    var icon: CEDIcon {
        switch self {
        case .heavy: .cloud
        case .gettingThrough: .sprout
        case .missingThem: .moon
        case .hopeful: .sunrise
        }
    }

    var iconColor: Color {
        switch self {
        case .heavy: CEDColor.accent
        case .gettingThrough: CEDColor.sproutGreen
        case .missingThem: CEDColor.rose
        case .hopeful: CEDColor.sunriseAmber
        }
    }
}

enum EnergyLevel: String, CaseIterable, Identifiable, Codable {
    case low, medium, high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// The "What feels hardest right now?" chips, in the order they appear.
enum HardestArea: String, CaseIterable, Identifiable, Codable {
    case feelingLonely = "feeling_lonely"
    case missingRelationship = "missing_relationship"
    case wantingAnswers = "wanting_answers"
    case resistingContact = "resisting_contact"
    case rebuildingConfidence = "rebuilding_confidence"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feelingLonely: "Feeling lonely"
        case .missingRelationship: "Missing the relationship"
        case .wantingAnswers: "Wanting answers"
        case .resistingContact: "Resisting contact"
        case .rebuildingConfidence: "Rebuilding confidence"
        }
    }
}

// MARK: - Reflection answers

/// "Did you think about your ex during the activity?"
enum ThoughtAboutEx: String, CaseIterable, Identifiable, Codable {
    case notReally = "not_really"
    case aLittle = "a_little"
    case aLot = "a_lot"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notReally: "Not really"
        case .aLittle: "A little"
        case .aLot: "A lot"
        }
    }
}

/// "How do you feel now compared to before?" Stored as chosen, never as a score.
enum MoodChange: String, CaseIterable, Identifiable, Codable {
    case worse
    case aboutTheSame = "about_the_same"
    case aLittleBetter = "a_little_better"
    case muchBetter = "much_better"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worse: "Worse"
        case .aboutTheSame: "About the same"
        case .aLittleBetter: "A little better"
        case .muchBetter: "Much better"
        }
    }
}

enum SampleData {
    static let urgeRange = 1...10
}

// MARK: - Reflection

/// The rule for "Add to my scrapbook": every input is required. The backend
/// checks the same things (POST /reflections), so an incomplete form can
/// never save a memory or complete an activity.
enum ReflectionDraft {
    /// The note with spaces and line breaks trimmed; nil if nothing is left.
    static func trimmedNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isComplete(hasPhoto: Bool, note: String,
                           thoughtAboutEx: ThoughtAboutEx?, moodChange: MoodChange?) -> Bool {
        hasPhoto && trimmedNote(note) != nil && thoughtAboutEx != nil && moodChange != nil
    }
}

// MARK: - Activity recommendations

/// One activity card, built from a recommendation sent by the backend.
struct Activity: Identifiable {
    let recommendationId: Int   // used to record "I'll try this"
    let activityId: Int
    let category: String        // e.g. "Mindfulness & Rest · 10 min"
    let title: String
    let instructions: String
    let whyItFits: String
    let icon: CEDIcon
    let background: Color   // soft tint behind the card art
    let accent: Color       // icon and category pill
    let isCompleted: Bool   // its reflection was saved
    var isSaved: Bool       // bookmarked with "Save for later"

    var id: Int { recommendationId }

    init(recommendation: RecommendationDTO) {
        self.init(activity: recommendation.activity,
                  recommendationId: recommendation.id,
                  reason: recommendation.reason,
                  isCompleted: recommendation.status == .completed,
                  isSaved: recommendation.isSaved)
    }

    /// `reason` (from the user's own check-in) comes first, then the
    /// activity's general description.
    init(activity: ActivityDTO, recommendationId: Int, reason: String? = nil,
         isCompleted: Bool = false, isSaved: Bool = false) {
        self.recommendationId = recommendationId
        self.isCompleted = isCompleted
        self.isSaved = isSaved
        activityId = activity.id
        category = "\(activity.categoryLabel) · \(Self.durationText(minutes: activity.durationMinutes))"
        title = activity.title
        instructions = activity.instructions
        whyItFits = [reason, activity.whyItFits].compactMap { $0 }.joined(separator: " ")
        (icon, background, accent) = Self.palette(for: activity.category)
    }

    /// Card colors and icon come from the activity's category,
    /// matching the prototype's three cards.
    static func palette(for category: String) -> (icon: CEDIcon, background: Color, accent: Color) {
        switch category {
        case "mindfulness_rest":
            (.sun, Color(hex: 0xFDE8D8), Color(hex: 0xC4633B))
        case "outdoor_movement":
            (.zap, Color(hex: 0xE8F0E0), Color(hex: 0x6BA84A))
        case "solo_exploration":
            (.users, Color(hex: 0xEAE0F0), Color(hex: 0x7B5E7B))
        default: // social_connection or anything new
            (.users, CEDColor.secondary, CEDColor.primary)
        }
    }

    /// 10 -> "10 min", 120 -> "2 hrs", 90 -> "1 hr 30 min"
    static func durationText(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let hourText = hours == 1 ? "1 hr" : "\(hours) hrs"
        let rest = minutes % 60
        return rest == 0 ? hourText : "\(hourText) \(rest) min"
    }
}

/// Which activity card is showing. The paging rules match the prototype's
/// ActivitiesScreen; the saved state comes from the backend.
struct ActivityDeck {
    /// The most cards shown at once (the backend never sends more either).
    static let maxCards = 3

    private(set) var activities: [Activity]
    private(set) var index = 0

    /// Keeps the first `maxCards` cards, skipping any repeat of an activity
    /// already in the deck. `activities` must not be empty.
    init(activities: [Activity]) {
        var seen = Set<Int>()
        self.activities = Array(
            activities.filter { seen.insert($0.activityId).inserted }.prefix(Self.maxCards)
        )
    }

    var current: Activity { activities[index] }

    /// The visible card (the pager reports it); out-of-range indexes are ignored.
    mutating func go(to newIndex: Int) {
        guard activities.indices.contains(newIndex) else { return }
        index = newIndex
    }

    /// Shows the saved state for every card of this activity.
    mutating func setSaved(_ isSaved: Bool, activityId: Int) {
        for i in activities.indices where activities[i].activityId == activityId {
            activities[i].isSaved = isSaved
        }
    }
}

// MARK: - Check-in answers

/// Answers for today's check-in, kept on screen until they're sent to the backend.
struct CheckInAnswers {
    var emotion: Emotion?
    var urge = 4
    var hasAnsweredUrge = false
    var energy: EnergyLevel?
    var hardestThings: Set<HardestArea> = []

    /// One flag per question, used by the four-part progress bar.
    var answeredSteps: [Bool] {
        [emotion != nil, hasAnsweredUrge, energy != nil, !hardestThings.isEmpty]
    }

    var isComplete: Bool { answeredSteps.allSatisfy { $0 } }

    mutating func toggleHardestThing(_ item: HardestArea) {
        if hardestThings.contains(item) {
            hardestThings.remove(item)
        } else {
            hardestThings.insert(item)
        }
    }

    /// The body for `POST /check-ins`, or nil if a question is unanswered.
    func makeRequest(on date: Date = .now) -> CheckInRequest? {
        guard isComplete, let emotion, let energy else { return nil }
        return CheckInRequest(
            feeling: emotion,
            contactUrge: urge,
            energyLevel: energy,
            // Same order as the chips on screen, so the saved list is predictable.
            hardestAreas: HardestArea.allCases.filter(hardestThings.contains),
            localDate: Self.localDateText(for: date)
        )
    }

    /// The user's own calendar day as "YYYY-MM-DD", in their time zone.
    static func localDateText(for date: Date) -> String {
        LocalDate.text(for: date)
    }
}
