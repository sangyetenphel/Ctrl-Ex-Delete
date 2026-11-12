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

// Patterns: structured from a newer backend, plain sentences from an older one.
let newer = InsightsText.patterns([
    (kind: "category", heading: "Connection seems to help", body: "Both … were followed by feeling better."),
    (kind: "summary", heading: nil, body: "You checked in on 3 days and completed 2 activities this week."),
], observations: ["Both … were followed by feeling better.", "You checked in on 3 days and completed 2 activities this week."])
check(newer.count == 2 && newer[0].heading == "Connection seems to help" && !newer[0].isSummary, "heading + sentence")
check(newer[1].heading == nil && newer[1].isSummary, "the totals line is the quieter summary")
let older = InsightsText.patterns(nil, observations: ["You completed 2 activities this week."])
check(older == [.init(heading: nil, body: "You completed 2 activities this week.", isSummary: false)],
      "older backend: its sentences, as they are")
check(InsightsText.patterns(nil, observations: []).isEmpty && InsightsText.patterns([], observations: []).isEmpty,
      "nothing to show: the empty-state text")

// At most three patterns: the urge pattern always, then categories; the
// totals line only when there would otherwise be fewer than two items.
typealias Item = (kind: String, heading: String?, body: String)
let solo: Item = (kind: "category", heading: "Finding comfort in your own company", body: "solo")
let social: Item = (kind: "category", heading: "Connection seems to help", body: "social")
let outdoor: Item = (kind: "category", heading: "Getting outside seems to help", body: "outdoor")
let rest: Item = (kind: "category", heading: "Slowing down seems to help", body: "rest")
let urge: Item = (kind: "urge", heading: "Some days are still harder than others", body: "urge")
let totals: Item = (kind: "summary", heading: nil, body: "You checked in on 8 days and completed 5 activities this month.")
let heads = { (items: [Item]) in InsightsText.patterns(items, observations: items.map(\.body)).map { $0.heading ?? "(totals)" } }
check(heads([solo, social, urge, totals]) == ["Finding comfort in your own company", "Connection seems to help",
                                              "Some days are still harder than others"],
      "Karla's month: two categories + the urge pattern, no totals line")
check(heads([urge, totals]) == ["Some days are still harder than others", "(totals)"],
      "Karla's week: the urge pattern, plus the totals so the card isn't a single line")
check(heads([outdoor, rest, solo, social, urge, totals]) == ["Getting outside seems to help", "Slowing down seems to help",
                                                            "Some days are still harder than others"],
      "four strong categories: the urge pattern still gets a place; never more than three")
check(heads([outdoor, rest, solo, social, totals]).count == 3 && !heads([outdoor, rest, solo, social, totals]).contains("(totals)"),
      "no urge pattern: three categories, no totals")
check(heads([totals]) == ["(totals)"], "only totals (e.g. check-ins but too little else): the totals line")
check(heads([solo, urge]) == ["Finding comfort in your own company", "Some days are still harder than others"],
      "two real patterns: no totals line")
check(InsightsText.patterns(nil, observations: ["a", "b", "c", "d", "e"]).count == 3, "older backend: at most three sentences")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("InsightsText: all passed")
