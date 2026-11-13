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
        "A taller bar means a stronger urge." + (isWeek ? "" : journeyWeeks)
    }

    static func moodSubtitle(isWeek: Bool) -> String {
        "A taller bar means you felt better after the activity." + (isWeek ? "" : journeyWeeks)
    }

    /// The month charts' bars are the user's own seven-day weeks (W1, W2, …).
    private static let journeyWeeks = " Each bar is a week of your journey."

    // MARK: Patterns

    struct Pattern: Equatable {
        let heading: String?
        let body: String
        let isSummary: Bool      // the closing totals line, shown quieter
    }

    /// At most this many items in "Patterns you might recognize".
    static let maxPatterns = 3

    /// The few patterns worth showing, in the backend's order:
    /// - the urge pattern ("Some days are still harder than others", …) always
    ///   gets a place;
    /// - category patterns fill the rest, in the backend's order;
    /// - the totals line ("You checked in on … and completed …") only when
    ///   there is no category or urge pattern at all.
    /// An older backend only sends `observations` (plain sentences): the
    /// first few are shown as they are, without headings.
    /// - urgeValues: the urge chart's values (nil = no check-in), used to say
    ///   whether a "steady" trend went up and down or stayed flat.
    static func patterns(_ structured: [(kind: String, heading: String?, body: String)]?,
                         observations: [String], urgeValues: [Double?] = [], isWeek: Bool = true) -> [Pattern] {
        guard let structured, !structured.isEmpty || observations.isEmpty else {
            return observations.prefix(maxPatterns).map { Pattern(heading: nil, body: $0, isSummary: false) }
        }
        let items = Array(structured.enumerated())
        let urge = items.filter { $0.element.kind == "urge" }.prefix(1)
        let others = items.filter { $0.element.kind != "urge" && $0.element.kind != "summary" }
        var keep = Set((Array(others.prefix(maxPatterns - urge.count)) + urge).map(\.offset))
        if keep.isEmpty, let summary = items.first(where: { $0.element.kind == "summary" }) {
            keep.insert(summary.offset)
        }
        // Positive category patterns are counted so the second and third
        // one can be worded differently from the first.
        var categoryIndex = 0
        return items.filter { keep.contains($0.offset) }.map { item in
            let (kind, heading, body) = item.element
            var line = displayLine(kind: kind, heading: heading, body: body)
            // Week only: the week chart has one bar per day; the month chart's
            // weekly averages would hide the day-to-day ups and downs.
            if kind == "urge", heading == "Your urge stayed fairly steady", isWeek {
                line = steadyUrgeLine(values: urgeValues.compactMap { $0 }, isWeek: isWeek) ?? line
            }
            if kind == "category", let heading, let varied = variedCategoryLine(heading: heading, body: body, index: categoryIndex) {
                line = varied
                categoryIndex += 1
            }
            return Pattern(heading: nil, body: line, isSummary: kind == "summary")
        }
    }

    /// The backend's "steady" means the later check-ins weren't clearly
    /// higher or lower than the earlier ones. The chart's own values tell
    /// whether the ratings moved around in between:
    ///   spread of 2 or more → "Your urge to reach out fluctuated this week,
    ///                          without a clear upward or downward trend."
    ///   spread under 2      → "Your urge to reach out stayed about the same this week."
    /// nil with fewer than two values (then the backend's sentence is used).
    static func steadyUrgeLine(values: [Double], isWeek: Bool) -> String? {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return nil }
        let period = isWeek ? "this week" : "this month"
        return high - low >= 2
            ? "Your urge to reach out fluctuated \(period), without a clear upward or downward trend."
            : "Your urge to reach out stayed about the same \(period)."
    }

    /// A positive category pattern in its own words, using the count and the
    /// category name from the backend's sentence ("all three", "both",
    /// "2 of 3"; "Solo Exploration"):
    ///   1st: "Taking time for yourself was followed by feeling better after
    ///         all three Solo Exploration activities."
    ///   2nd: "Connecting with others also seemed supportive, with improved
    ///         moods after both Social Connection activities."
    ///   3rd: "Getting outside seemed to help too, with improved moods after
    ///         2 of 3 Outdoor & Movement activities."
    /// nil when the heading or sentence isn't one it knows (then the plainer
    /// `displayLine` is used), so nothing is ever guessed.
    static func variedCategoryLine(heading: String, body: String, index: Int) -> String? {
        let leads = [
            "Finding comfort in your own company": "Taking time for yourself",
            "Connection seems to help": "Connecting with others",
            "Getting outside seems to help": "Getting outside",
            "Slowing down seems to help": "Slowing down",
        ]
        guard let lead = leads[heading], let (amount, label) = countAndCategory(firstSentence(body)) else { return nil }
        let what = "\(amount) \(label) activities"
        switch index {
        case 0: return "\(lead) was followed by feeling better after \(what)."
        case 1: return "\(lead) also seemed supportive, with improved moods after \(what)."
        default: return "\(lead) seemed to help too, with improved moods after \(what)."
        }
    }

    /// ("all three", "Solo Exploration") from either of the backend's two
    /// sentence shapes:
    ///   "You reported feeling better after all three Solo Exploration activities this month."
    ///   "Both Social Connection activities this week were followed by feeling better."
    private static func countAndCategory(_ sentence: String) -> (String, String)? {
        let amount = #"(both|all \w+|\d+ of \d+)"#
        let period = #"this (?:week|month)"#
        let shapes = [
            #"^You reported feeling better after \#(amount) (.+) activities \#(period)\.$"#,
            #"^\#(amount) (.+) activities \#(period) were followed by feeling better\.$"#,
        ]
        for shape in shapes {
            guard let regex = try? NSRegularExpression(pattern: shape, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
                  let amountRange = Range(match.range(at: 1), in: sentence),
                  let labelRange = Range(match.range(at: 2), in: sentence) else { continue }
            return (sentence[amountRange].lowercased(), String(sentence[labelRange]))
        }
        return nil
    }

    /// One concise, informative sentence per pattern, built from the
    /// backend's own sentence (which states what was reported, with the
    /// numbers: "You reported feeling better after all three Solo
    /// Exploration activities this month. Making time for yourself may be
    /// worth continuing."):
    /// - category patterns keep that first, factual sentence and replace the
    ///   longer advice sentence with a short, careful clause
    ///   ("…, suggesting that time for yourself may be helping.");
    /// - the urge pattern's "has generally decreased" is said more exactly as
    ///   "was generally lower in your later check-ins" (that is what the
    ///   backend compares);
    /// - everything else (steady or higher urges, mixed or not-better
    ///   results, the totals fallback) is the backend's sentence as it is.
    /// Nothing is invented: every number and trend comes from the backend.
    static func displayLine(kind: String, heading: String?, body: String) -> String {
        if kind == "category", let heading, let clause = categoryClause(heading) {
            return String(firstSentence(body).dropLast()) + ", suggesting that " + clause + "."
        }
        if kind == "urge" {
            return body.replacingOccurrences(of: "Your urge to reach out has generally decreased",
                                             with: "Your urge to reach out was generally lower in your later check-ins")
        }
        return body
    }

    /// The careful closing clause for a category that was mostly followed by
    /// feeling better (only those have these headings).
    private static func categoryClause(_ heading: String) -> String? {
        switch heading {
        case "Finding comfort in your own company": return "time for yourself may be helping"
        case "Connection seems to help": return "connecting with others may be supportive"
        case "Getting outside seems to help": return "getting outside may be helping"
        case "Slowing down seems to help": return "slowing down may be helping"
        default:
            // A category the catalog may add later: "<Label> seems to help".
            return heading.hasSuffix(" seems to help") ? "these activities may be helping" : nil
        }
    }

    /// "A. B." → "A." (the whole text when there's only one sentence).
    private static func firstSentence(_ text: String) -> String {
        guard let range = text.range(of: ". ") else { return text.hasSuffix(".") ? text : text + "." }
        return String(text[..<range.lowerBound]) + "."
    }

}
