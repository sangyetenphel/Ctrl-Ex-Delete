import SwiftUI

// What the Progress screen shows, built only from `GET /insights`.
// There is deliberately no sample data here, so sample numbers can never be
// mistaken for the user's real progress.

enum InsightsPeriod: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }
    var label: String { self == .week ? "This week" : "This month" }
}

/// One bar. `value` nil = nothing recorded (shown as a short grey stub).
struct ChartPoint: Identifiable {
    let label: String      // "Mon", "W1" or a mood answer
    let value: Int?
    var id: String { label }
}

struct ActivityShare: Identifiable {
    let label: String
    let count: Int
    let percent: Int
    let color: Color
    var id: String { label }
}

struct InsightsData {
    let period: InsightsPeriod      // the period these numbers are for
    let hasData: Bool
    let urges: [ChartPoint]
    let moods: [ChartPoint]
    let moodTotal: Int
    let activities: [ActivityShare]
    let observations: [String]
    let takeawayHeadline: String
    let takeawayBody: String

    init(_ dto: InsightsDTO) {
        period = InsightsPeriod(rawValue: dto.period) ?? .week
        hasData = dto.hasData
        urges = dto.urges.map { ChartPoint(label: $0.label, value: $0.value) }
        // Mood answers are counted as given: a bar's height is how many
        // times that answer was chosen. Zero is shown like "nothing yet".
        moods = dto.moods.map { ChartPoint(label: $0.label, value: $0.count > 0 ? $0.count : nil) }
        moodTotal = dto.moods.reduce(0) { $0 + $1.count }
        activities = dto.categories.map {
            ActivityShare(label: $0.label, count: $0.count, percent: $0.percent,
                          color: Self.color(for: $0.category))
        }
        observations = dto.observations
        takeawayHeadline = dto.takeaway.headline
        takeawayBody = dto.takeaway.body
    }

    /// The prototype's colors for each category.
    private static func color(for category: String) -> Color {
        switch category {
        case "outdoor_movement": Color(hex: 0x6BA84A)
        case "mindfulness_rest": Color(hex: 0xD4844A)
        case "solo_exploration": Color(hex: 0x7B5E7B)
        default: CEDColor.rose
        }
    }
}
