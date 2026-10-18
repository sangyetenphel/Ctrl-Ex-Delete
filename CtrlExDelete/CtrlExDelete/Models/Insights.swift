import SwiftUI

// What the Progress screen shows, built only from `GET /insights`.
// There is deliberately no sample data here, so sample numbers can never be
// mistaken for the user's real progress.

enum InsightsPeriod: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }
    var label: String { self == .week ? "This week" : "This month" }
}

/// One bar. `value` sizes the bar on a fixed 0–10 scale and is never shown
/// as a number; nil = nothing recorded (a gap: a short grey stub, not zero).
struct ChartPoint: Identifiable {
    let label: String              // "Mon" … "Sun", or "W1" … "W5"
    let value: Double?
    let accessibilityText: String  // the date and what was recorded, in words
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
    let urges: [ChartPoint]        // check-in urge answers
    let moods: [ChartPoint]        // answers after completed activities
    let hasUrges: Bool
    let hasMoods: Bool
    let activities: [ActivityShare]
    let observations: [String]
    let takeawayHeadline: String
    let takeawayBody: String

    init(_ dto: InsightsDTO) {
        period = InsightsPeriod(rawValue: dto.period) ?? .week
        hasData = dto.hasData
        let period = period
        urges = dto.urges.map { point in
            ChartPoint(label: point.label,
                       value: point.value.map(Double.init),
                       accessibilityText: Self.urgeDescription(point, period: period))
        }
        // The mood bars come straight from the backend, which turns each
        // answer into a fixed internal score (insights.MOOD_SCORES). The
        // score only sets the height; it isn't something the user entered.
        // An older backend without `mood_points` shows an empty week.
        moods = (dto.moodPoints ?? dto.urges.map {
            MoodPointDTO(label: $0.label, start: $0.start, value: nil, answers: [])
        }).map { point in
            ChartPoint(label: point.label,
                       value: point.value,
                       accessibilityText: Self.moodDescription(point, period: period))
        }
        hasUrges = urges.contains { $0.value != nil }
        hasMoods = moods.contains { $0.value != nil }
        activities = dto.categories.map {
            ActivityShare(label: $0.label, count: $0.count, percent: $0.percent,
                          color: Self.color(for: $0.category))
        }
        observations = dto.observations
        takeawayHeadline = dto.takeaway.headline
        takeawayBody = dto.takeaway.body
    }

    // MARK: Accessibility descriptions

    /// "Monday, October 12" for a day, or "Week of October 5" for a week bar.
    private static func dateText(_ start: String, period: InsightsPeriod) -> String {
        period == .week
            ? LocalDate.format(start, .dateTime.weekday(.wide).month(.wide).day())
            : "Week of " + LocalDate.format(start, .dateTime.month(.wide).day())
    }

    /// The urge is a number the user chose at check-in, so it's said as is.
    private static func urgeDescription(_ point: UrgePointDTO, period: InsightsPeriod) -> String {
        let date = dateText(point.start, period: period)
        guard let value = point.value else { return "\(date): no check-in" }
        if point.checkIns == 1 {
            return "\(date): you rated your urge to contact your ex \(value) out of 10"
        }
        return "\(date): your urge to contact your ex averaged \(value) out of 10 across \(point.checkIns) check-ins"
    }

    /// Mood is described with the answers the user actually gave.
    private static func moodDescription(_ point: MoodPointDTO, period: InsightsPeriod) -> String {
        let date = dateText(point.start, period: period)
        guard !point.answers.isEmpty else { return "\(date): no completed activity" }
        if point.answers.count == 1 {
            return "\(date): after one activity, you said you felt \(point.answers[0].label.lowercased())"
        }
        let answers = point.answers.map { $0.label.lowercased() }.formatted(.list(type: .and))
        return "\(date): after \(point.answers.count) activities, you said you felt \(answers)"
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
