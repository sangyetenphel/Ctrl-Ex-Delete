import SwiftUI

// Sample numbers for the Progress / Insights screen, copied from the prototype.
// `nil` means there was no check-in (or no activity) that day.

enum InsightsPeriod: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }
    var label: String { self == .week ? "This week" : "This month" }
}

struct ChartPoint: Identifiable {
    let label: String   // "Mon" or "W1"
    let value: Int?     // 1–10
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
    let urges: [ChartPoint]
    let moods: [ChartPoint]
    let activities: [ActivityShare]
    let observations: [String]
    let takeawayHeadline: String
    let takeawayBody: String

    static func sample(for period: InsightsPeriod) -> InsightsData {
        period == .week ? week : month
    }

    private static let outdoorGreen = Color(hex: 0x6BA84A)
    private static let restOrange = Color(hex: 0xD4844A)
    private static let soloPlum = Color(hex: 0x7B5E7B)

    static let week = InsightsData(
        urges: [
            ChartPoint(label: "Mon", value: 7), ChartPoint(label: "Tue", value: 6), ChartPoint(label: "Wed", value: 8),
            ChartPoint(label: "Thu", value: 5), ChartPoint(label: "Fri", value: 4), ChartPoint(label: "Sat", value: nil),
            ChartPoint(label: "Sun", value: 4),
        ],
        moods: [
            ChartPoint(label: "Mon", value: 4), ChartPoint(label: "Tue", value: 5), ChartPoint(label: "Wed", value: nil),
            ChartPoint(label: "Thu", value: 6), ChartPoint(label: "Fri", value: 7), ChartPoint(label: "Sat", value: nil),
            ChartPoint(label: "Sun", value: 7),
        ],
        activities: [
            ActivityShare(label: "Outdoor & movement", count: 3, percent: 50, color: outdoorGreen),
            ActivityShare(label: "Mindfulness & rest", count: 2, percent: 33, color: restOrange),
            ActivityShare(label: "Solo exploration", count: 1, percent: 17, color: soloPlum),
            ActivityShare(label: "Social connection", count: 0, percent: 0, color: CEDColor.rose),
        ],
        observations: [
            "Your urge to reach out has eased since Monday.",
            "You felt more settled on days with outdoor activities.",
            "You completed 5 activities this week.",
        ],
        takeawayHeadline: "Outdoor time may be helping.",
        takeawayBody: "You reported feeling more settled after outdoor activities this week."
    )

    static let month = InsightsData(
        urges: [
            ChartPoint(label: "W1", value: 8), ChartPoint(label: "W2", value: 7),
            ChartPoint(label: "W3", value: 5), ChartPoint(label: "W4", value: 4),
        ],
        moods: [
            ChartPoint(label: "W1", value: 3), ChartPoint(label: "W2", value: 5),
            ChartPoint(label: "W3", value: 6), ChartPoint(label: "W4", value: 7),
        ],
        activities: [
            ActivityShare(label: "Outdoor & movement", count: 9, percent: 45, color: outdoorGreen),
            ActivityShare(label: "Mindfulness & rest", count: 6, percent: 30, color: restOrange),
            ActivityShare(label: "Solo exploration", count: 3, percent: 15, color: soloPlum),
            ActivityShare(label: "Social connection", count: 2, percent: 10, color: CEDColor.rose),
        ],
        observations: [
            "Your urge to reach out has been gradually softening over the month.",
            "Mood ratings after activities have climbed steadily week by week.",
            "You completed 20 activities this month \u{2014} a meaningful stretch.",
        ],
        takeawayHeadline: "A steady month of small steps.",
        takeawayBody: "Your mood after activities has risen week on week, and urges have slowly lost their edge."
    )
}
