import SwiftUI

// What the Progress screen shows, built only from `GET /insights`.
// There is deliberately no sample data here, so sample numbers can never be
// mistaken for the user's real progress.

enum InsightsPeriod: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }
    var label: String { self == .week ? "This week" : "This month" }
}

/// One bar. `value` sizes the bar on a fixed 0–10 scale and is never drawn
/// as a number; nil = nothing recorded (a gap: a short grey mark, not zero).
struct ChartPoint: Identifiable {
    let label: String              // "Mon" … "Sun", or "W1", "W2", … (the user's own weeks)
    let value: Double?
    let accessibilityText: String  // the date and what was recorded, in words (VoiceOver)
    var mood: InsightsText.MoodBar = .noActivity   // mood chart only: sets the bar's color
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
    let activitiesCaption: String  // "Activities completed this week" / "… in November"
    let patterns: [InsightsText.Pattern]
    let takeawayHeadline: String
    let takeawayBody: String

    init(_ dto: InsightsDTO) {
        period = InsightsPeriod(rawValue: dto.period) ?? .week
        hasData = dto.hasData
        let period = period
        urges = dto.urges.map { point in
            ChartPoint(label: point.label,
                       value: point.value.map(Double.init),
                       accessibilityText: InsightsText.urge(date: Self.dateText(point.start, period: period),
                                                            value: point.value, checkIns: point.checkIns))
        }
        // The mood bars come straight from the backend, which turns each
        // answer into a fixed internal score (insights.MOOD_SCORES). The
        // score only sets the height; it isn't something the user entered.
        // An older backend without `mood_points` shows an empty week.
        // Both charts have the same bars, so a mood gap can say whether the
        // user checked in that day (or week) without finishing an activity.
        let checkInsByBar = Dictionary(dto.urges.map { ($0.start, $0.checkIns) }, uniquingKeysWith: +)
        moods = (dto.moodPoints ?? dto.urges.map {
            MoodPointDTO(label: $0.label, start: $0.start, value: nil, answers: [])
        }).map { point in
            ChartPoint(label: point.label,
                       value: point.value,
                       accessibilityText: InsightsText.mood(date: Self.dateText(point.start, period: period),
                                                            answers: point.answers.map(\.label),
                                                            checkedIn: (checkInsByBar[point.start] ?? 0) > 0),
                       mood: InsightsText.moodBar(value: point.value))
        }
        hasUrges = urges.contains { $0.value != nil }
        hasMoods = moods.contains { $0.value != nil }
        activities = dto.categories.map {
            ActivityShare(label: $0.label, count: $0.count, percent: $0.percent,
                          color: Self.color(for: $0.category))
        }
        activitiesCaption = InsightsText.categoryCaption(
            isWeek: period == .week,
            monthName: LocalDate.format(dto.start, .dateTime.month(.wide)))
        patterns = InsightsText.patterns(dto.patterns?.map { ($0.kind, $0.heading, $0.body) },
                                         observations: dto.observations,
                                         urgeValues: dto.urges.map { $0.value.map(Double.init) },
                                         isWeek: period == .week)
        takeawayHeadline = dto.takeaway.headline
        takeawayBody = dto.takeaway.body
    }

    // MARK: Dates

    /// "Monday, October 12" for a day, or "Week of October 5" for a week bar.
    private static func dateText(_ start: String, period: InsightsPeriod) -> String {
        period == .week
            ? LocalDate.format(start, .dateTime.weekday(.wide).month(.wide).day())
            : "Week of " + LocalDate.format(start, .dateTime.month(.wide).day())
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
