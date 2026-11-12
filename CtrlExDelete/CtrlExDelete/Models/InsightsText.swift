import Foundation

// Words and states for the Progress screen, kept free of SwiftUI so
// DevTests/run.sh can test them on the Mac. Everything here is built from
// what `GET /insights` sent; nothing is invented.

enum InsightsText {

    // MARK: Bars

    /// What one bar of "Mood after activities" stands for, which sets its color.
    enum MoodBar: Equatable {
        case noActivity          // grey baseline mark
        case notBetter           // muted bar: "about the same" or "worse" (on average)
        case better              // positive bar: "a little" or "much better" (on average)
    }

    /// Bars above the "about the same" score (5) lean better; the same rule
    /// sets the bar's height, so color and height always agree.
    static func moodBar(value: Double?) -> MoodBar {
        guard let value else { return .noActivity }
        return value > 5 ? .better : .notBetter
    }

    /// "Tuesday, November 10: urge to reach out, 7 out of 10".
    static func urge(date: String, value: Int?, checkIns: Int) -> String {
        guard let value else { return "\(date): no check-in" }
        if checkIns <= 1 { return "\(date): urge to reach out, \(value) out of 10" }
        return "\(date): urge to reach out averaged \(value) out of 10 across \(checkIns) check-ins"
    }

    /// Says what was recorded, keeping apart "no check-in", "checked in but
    /// no activity" and the answers given after activities.
    /// - Parameters:
    ///   - answers: the answers' labels as the user saw them ("Much better").
    ///   - checkedIn: whether the same bar of the urge chart has a check-in.
    static func mood(date: String, answers: [String], checkedIn: Bool) -> String {
        let felt = answers.map { $0.lowercased() }
        switch felt.count {
        case 0:
            return checkedIn ? "\(date): checked in, no activity completed" : "\(date): no check-in or activity"
        case 1:
            return "\(date): after one activity, you felt \(felt[0])"
        default:
            return "\(date): after \(felt.count) activities, you felt \(grouped(felt))"
        }
    }

    /// "worse and much better", or with repeats "a little better 3 times and
    /// about the same once" (most frequent first, then first given).
    private static func grouped(_ felt: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for answer in felt {
            if counts[answer] == nil { order.append(answer) }
            counts[answer, default: 0] += 1
        }
        if order.count == felt.count { return felt.formatted(.list(type: .and)) }
        let times = { (n: Int) in n == 1 ? "once" : n == 2 ? "twice" : "\(n) times" }
        return order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map { "\($0.element) \(times(counts[$0.element]!))" }
            .formatted(.list(type: .and))
    }

    // MARK: Captions

    /// Under "What you made time for": which days the category counts cover.
    static func categoryCaption(isWeek: Bool, monthName: String) -> String {
        isWeek ? "Activities completed this week" : "Activities completed in \(monthName)"
    }

    static func urgeSubtitle(isWeek: Bool) -> String {
        let base = "How strong your urge to contact your ex was. A taller bar means a stronger urge; it\u{2019}s information, not a grade."
        return isWeek ? base : base + " Each bar is one week of your journey."
    }

    static func moodSubtitle(isWeek: Bool) -> String {
        let base = "How you felt after completing an activity, compared with before."
        return isWeek ? base : base + " Each bar is one week of your journey."
    }

    // MARK: Patterns

    struct Pattern: Equatable {
        let heading: String?
        let body: String
        let isSummary: Bool      // the closing totals line, shown quieter
    }

    /// `patterns` from a newer backend; an older one only sends `observations`
    /// (plain sentences), which are shown as they are, without headings.
    static func patterns(_ structured: [(kind: String, heading: String?, body: String)]?,
                         observations: [String]) -> [Pattern] {
        guard let structured, !structured.isEmpty || observations.isEmpty else {
            return observations.map { Pattern(heading: nil, body: $0, isSummary: false) }
        }
        return structured.map { Pattern(heading: $0.heading, body: $0.body, isSummary: $0.kind == "summary") }
    }
}
