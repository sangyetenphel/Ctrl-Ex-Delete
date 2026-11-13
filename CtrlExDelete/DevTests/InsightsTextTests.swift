// Tests for InsightsText (Models/InsightsText.swift): the Progress screen's
// chart states, spoken/tapped descriptions, captions and patterns.
// Run with ./DevTests/run.sh.
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition { print("  ok    \(message)") } else { failures += 1; print("  FAIL  \(message) (line \(line))") }
}

// The four mood answers' fixed scores (backend MOOD_SCORES) and a gap.
check(InsightsText.moodBar(value: nil) == .noActivity, "no completed activity: the grey mark, no colored bar")
check(InsightsText.moodBar(value: 2) == .notBetter, "worse (2): a short, muted bar")
check(InsightsText.moodBar(value: 5) == .notBetter, "about the same (5): a muted bar")
check(InsightsText.moodBar(value: 7) == .better, "a little better (7): a positive bar")
check(InsightsText.moodBar(value: 9) == .better, "much better (9): a positive bar")
check(InsightsText.moodBar(value: 4.5) == .notBetter, "worse + a little better on one day (4.5): muted, like its height")
check(InsightsText.moodBar(value: 5.5) == .better, "worse + much better on one day (5.5): leans better, like its height")

// Urge descriptions (VoiceOver and tap).
let tue = "Tuesday, November 10"
check(InsightsText.urge(date: tue, value: 7, checkIns: 1) == "Tuesday, November 10: urge to reach out, 7 out of 10",
      "one check-in: the exact value out of 10")
check(InsightsText.urge(date: "Week of November 8", value: 5, checkIns: 3)
      == "Week of November 8: urge to reach out averaged 5 out of 10 across 3 check-ins", "a week: the average")
check(InsightsText.urge(date: tue, value: nil, checkIns: 0) == "Tuesday, November 10: no check-in",
      "no check-in is said as such, never as 0")

// Mood descriptions keep the four situations apart.
check(InsightsText.mood(date: tue, answers: [], checkedIn: false) == "Tuesday, November 10: no check-in or activity",
      "1. no check-in")
check(InsightsText.mood(date: tue, answers: [], checkedIn: true) == "Tuesday, November 10: checked in, no activity completed",
      "2. check-in but no completed activity")
check(InsightsText.mood(date: tue, answers: ["About the same"], checkedIn: true)
      == "Tuesday, November 10: after one activity, you felt about the same", "3. completed, no improvement")
check(InsightsText.mood(date: tue, answers: ["Much better"], checkedIn: true)
      == "Tuesday, November 10: after one activity, you felt much better", "4. completed, felt better")
check(InsightsText.mood(date: tue, answers: ["Worse", "Much better"], checkedIn: true)
      == "Tuesday, November 10: after 2 activities, you felt worse and much better", "two activities on one day: both answers")
check(InsightsText.mood(date: "Week of October 25",
                        answers: ["About the same", "A little better", "A little better", "A little better"], checkedIn: true)
      == "Week of October 25: after 4 activities, you felt a little better 3 times and about the same once",
      "repeated answers are grouped, most frequent first")
check(InsightsText.mood(date: tue, answers: ["Worse", "Much better", "Worse"], checkedIn: true)
      == "Tuesday, November 10: after 3 activities, you felt worse twice and much better once", "twice / once")

// Captions follow the selected period.
check(InsightsText.categoryCaption(isWeek: true, monthName: "November") == "Activities completed this week", "week caption")
check(InsightsText.categoryCaption(isWeek: false, monthName: "November") == "Activities completed in November", "month caption")
check(InsightsText.urgeSubtitle(isWeek: true) == "A taller bar means a stronger urge.", "urge subtitle (week): short")
check(InsightsText.urgeSubtitle(isWeek: false) == "A taller bar means a stronger urge. Each bar is a week of your journey.",
      "urge subtitle (month): says the bars are journey weeks")
check(InsightsText.moodSubtitle(isWeek: true) == "A taller bar means you felt better after the activity.", "mood subtitle (week): short")
check(InsightsText.moodSubtitle(isWeek: false).hasSuffix("Each bar is a week of your journey."), "mood subtitle (month)")

// Patterns: one informative sentence each (no heading), built from the
// backend's own sentence; an older backend's plain sentences are shown as they are.
let soloBody = "You reported feeling better after all three Solo Exploration activities this month. Making time for yourself may be worth continuing."
let socialBody = "Both Social Connection activities this month were followed by feeling better. Spending time with people you trust may be worth making room for."
let urgeBody = "Your urge to reach out has generally decreased this month, even though it rose on some days."
let newer = InsightsText.patterns([
    (kind: "category", heading: "Connection seems to help", body: socialBody),
    (kind: "summary", heading: nil, body: "You checked in on 3 days and completed 2 activities this week."),
], observations: [])
check(newer == [.init(heading: nil, body: "Both Social Connection activities this month were followed by feeling better, suggesting that connecting with others may be supportive.", isSummary: false)],
      "category: the backend's factual sentence + a careful clause; no heading; totals left out")
let onlyTotals = InsightsText.patterns([(kind: "summary", heading: nil, body: "You checked in on 1 day this week.")], observations: [])
check(onlyTotals == [.init(heading: nil, body: "You checked in on 1 day this week.", isSummary: true)],
      "no real pattern: the totals line as the quieter fallback")
let older = InsightsText.patterns(nil, observations: ["You completed 2 activities this week."])
check(older == [.init(heading: nil, body: "You completed 2 activities this week.", isSummary: false)],
      "older backend: its sentences, as they are")
check(InsightsText.patterns(nil, observations: []).isEmpty && InsightsText.patterns([], observations: []).isEmpty,
      "nothing to show: the empty-state text")

// Every kind of pattern the backend sends.
let line = { (k: String, h: String?, b: String) in InsightsText.displayLine(kind: k, heading: h, body: b) }
check(line("category", "Finding comfort in your own company", soloBody)
      == "You reported feeling better after all three Solo Exploration activities this month, suggesting that time for yourself may be helping.",
      "solo: keeps the real count (all three) and says 'may be helping', not 'caused'")
check(line("category", "Getting outside seems to help", "You reported feeling better after 2 of 3 Outdoor & Movement activities this week. Stepping outside or moving your body may be worth keeping in your days.")
      == "You reported feeling better after 2 of 3 Outdoor & Movement activities this week, suggesting that getting outside may be helping.",
      "outdoor: '2 of 3' stays as the backend counted it")
check(line("category", "Slowing down seems to help", "Both Mindfulness & Rest activities this week were followed by feeling better. Quiet moments to rest may be worth protecting.")
      == "Both Mindfulness & Rest activities this week were followed by feeling better, suggesting that slowing down may be helping.", "rest")
check(line("category", "Creative Arts seems to help", "You reported feeling better after both Creative Arts activities this week. It may be worth making room for more of these.")
      == "You reported feeling better after both Creative Arts activities this week, suggesting that these activities may be helping.", "a future category")
check(line("urge", "Some days are still harder than others", urgeBody)
      == "Your urge to reach out was generally lower in your later check-ins this month, even though it rose on some days.",
      "urge lower with harder days: says what was compared (later check-ins)")
check(line("urge", "Your urge stayed fairly steady", "Your urge ratings this week stayed in a similar range.")
      == "Your urge ratings this week stayed in a similar range.", "steady urge: the backend's sentence, no invented improvement")
let higher = "Your later check-ins this week had higher urge ratings than your earlier ones. That\u{2019}s worth noticing, not a setback."
check(line("urge", "Urges can rise and fall", higher) == higher, "higher urge: shown honestly, as the backend says it")
let mixed = "How you felt after Solo Exploration activities this month was mixed. It\u{2019}s okay to keep exploring."
check(line("category", "Still finding what fits", mixed) == mixed, "mixed results: shown honestly, no positive clause")
let notBetter = "The Mindfulness & Rest activities you completed this week weren\u{2019}t followed by feeling better. Something different might suit you right now, and that\u{2019}s okay."
check(line("category", "Not every activity fits every day", notBetter) == notBetter, "not better: shown honestly, no positive clause")
check(line("summary", nil, "You checked in on 9 days and completed 5 activities this month.") == "You checked in on 9 days and completed 5 activities this month.", "totals: as is")

// At most three patterns: the urge pattern always, then categories; the
// totals line only when there is no category or urge pattern at all.
typealias Item = (kind: String, heading: String?, body: String)
let solo: Item = (kind: "category", heading: "Finding comfort in your own company", body: soloBody)
let social: Item = (kind: "category", heading: "Connection seems to help", body: socialBody)
let outdoor: Item = (kind: "category", heading: "Getting outside seems to help", body: "Outdoor sentence. Advice.")
let rest: Item = (kind: "category", heading: "Slowing down seems to help", body: "Rest sentence. Advice.")
let urge: Item = (kind: "urge", heading: "Some days are still harder than others", body: urgeBody)
let totals: Item = (kind: "summary", heading: nil, body: "You checked in on 9 days and completed 5 activities this month.")
let lines = { (items: [Item]) in InsightsText.patterns(items, observations: []).map(\.body) }
check(lines([solo, social, urge, totals]) == [
        "You reported feeling better after all three Solo Exploration activities this month, suggesting that time for yourself may be helping.",
        "Both Social Connection activities this month were followed by feeling better, suggesting that connecting with others may be supportive.",
        "Your urge to reach out was generally lower in your later check-ins this month, even though it rose on some days."],
      "a month like Karla's: three informative sentences, no totals")
check(lines([(kind: "urge", heading: "Your urge stayed fairly steady", body: "Your urge ratings this week stayed in a similar range."), totals])
      == ["Your urge ratings this week stayed in a similar range."], "a week with one pattern: just that sentence")
check(lines([outdoor, rest, solo, social, urge, totals]).count == 3 && lines([outdoor, rest, solo, social, urge, totals]).last == line("urge", urge.heading, urgeBody),
      "four strong categories: the urge pattern still gets a place; never more than three")
check(!lines([outdoor, rest, solo, social, totals]).contains(totals.body) && lines([outdoor, rest, solo, social, totals]).count == 3,
      "no urge pattern: three categories, no totals")
check(lines([totals]) == [totals.body], "no meaningful pattern at all: the totals line as the neutral fallback")
check(InsightsText.patterns(nil, observations: ["a", "b", "c", "d", "e"]).count == 3, "older backend: at most three sentences")
check(InsightsText.patterns([solo, social, urge], observations: []).allSatisfy { $0.heading == nil }, "no bold headings anywhere")
check(!lines([solo, social, urge]).contains { $0.lowercased().contains("caused") || $0.lowercased().contains("because") },
      "careful language: nothing says an activity caused the change")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("InsightsText: all passed")
