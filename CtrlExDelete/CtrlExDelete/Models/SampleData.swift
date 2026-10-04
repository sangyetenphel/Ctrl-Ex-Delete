import SwiftUI

// Local sample data for the prototype. Nothing here is saved or sent anywhere.

// MARK: - Check-in options

enum Emotion: String, CaseIterable, Identifiable {
    case heavy
    case gettingThrough
    case missingThem
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

enum EnergyLevel: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum SampleData {
    static let hardestThings = [
        "Feeling lonely",
        "Missing the relationship",
        "Wanting answers",
        "Resisting contact",
        "Rebuilding confidence",
    ]

    static let urgeRange = 1...10
}

// MARK: - Activity recommendations

struct Activity: Identifiable {
    let category: String
    let title: String
    let instructions: String
    let whyItFits: String
    let icon: CEDIcon
    let background: Color   // soft tint behind the card art
    let accent: Color       // icon and category pill

    var id: String { title }
}

extension SampleData {
    /// The three recommendations from the prototype. Like the prototype,
    /// they are the same every day and don't depend on check-in answers.
    static let activities = [
        Activity(
            category: "Gentle Reset · 10 min",
            title: "Sit somewhere with sunlight.",
            instructions: "No productivity needed. Notice three things you can see and take five slow breaths.",
            whyItFits: "Your energy is low and the urge to reach out is moderate. This activity gives your nervous system a soft reset.",
            icon: .sun,
            background: Color(hex: 0xFDE8D8),
            accent: Color(hex: 0xC4633B)
        ),
        Activity(
            category: "Fresh Air · 20 min",
            title: "Take a 20-minute walk without checking their social media.",
            instructions: "Leave your phone in your pocket. Pay attention to sounds around you — birds, wind, footsteps.",
            whyItFits: "Movement helps interrupt rumination loops. Walking without scrolling gives your mind space to settle.",
            icon: .zap,
            background: Color(hex: 0xE8F0E0),
            accent: Color(hex: 0x6BA84A)
        ),
        Activity(
            category: "Solo Adventure · 2 hrs",
            title: "Visit a café, movie, or event by yourself.",
            instructions: "Choose somewhere you\u{2019}ve been curious about. You don\u{2019}t need company to enjoy something new.",
            whyItFits: "Building comfort with your own company is one of the most powerful steps in healing.",
            icon: .users,
            background: Color(hex: 0xEAE0F0),
            accent: Color(hex: 0x7B5E7B)
        ),
    ]
}

/// Which activity card is showing and which ones were saved.
/// The rules match the prototype's ActivitiesScreen.
struct ActivityDeck {
    let activities: [Activity]
    private(set) var index = 0
    private(set) var savedIndices: Set<Int> = []

    init(activities: [Activity] = SampleData.activities) {
        self.activities = activities
    }

    var current: Activity { activities[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < activities.count - 1 }
    var isCurrentSaved: Bool { savedIndices.contains(index) }

    mutating func goBack() {
        index = max(0, index - 1)
    }

    /// Skip uses this too: it moves to the next card and stays on the last one.
    mutating func goForward() {
        index = min(activities.count - 1, index + 1)
    }

    mutating func go(to newIndex: Int) {
        guard activities.indices.contains(newIndex) else { return }
        index = newIndex
    }

    /// Saves the current card. Returns `true` only the first time,
    /// which is when the "Saved for another day" toast should appear.
    mutating func saveCurrent() -> Bool {
        savedIndices.insert(index).inserted
    }
}

// MARK: - Check-in answers

/// Temporary answers for today's check-in. They live only while the app is open.
struct CheckInAnswers {
    var emotion: Emotion?
    var urge = 4
    var hasAnsweredUrge = false
    var energy: EnergyLevel?
    var hardestThings: Set<String> = []

    /// One flag per question, used by the four-part progress bar.
    var answeredSteps: [Bool] {
        [emotion != nil, hasAnsweredUrge, energy != nil, !hardestThings.isEmpty]
    }

    var isComplete: Bool { answeredSteps.allSatisfy { $0 } }

    mutating func toggleHardestThing(_ item: String) {
        if hardestThings.contains(item) {
            hardestThings.remove(item)
        } else {
            hardestThings.insert(item)
        }
    }
}
