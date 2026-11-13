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

// Patterns: one short line each (no heading), built from the backend's
// structured patterns; an older backend's plain sentences are shown as they are.
let newer = InsightsText.patterns([
    (kind: "category", heading: "Connection seems to help", body: "Both … were followed by feeling better."),
    (kind: "summary", heading: nil, body: "You checked in on 3 days and completed 2 activities this week."),
], observations: ["Both … were followed by feeling better.", "You checked in on 3 days and completed 2 activities this week."])
check(newer == [.init(heading: nil, body: "Social connection seemed to help this week.", isSummary: false)],
      "one short line, no heading; totals left out")
let onlyTotals = InsightsText.patterns([(kind: "summary", heading: nil, body: "You checked in on 1 day this week.")], observations: ["You checked in on 1 day this week."])
check(onlyTotals == [.init(heading: nil, body: "You checked in on 1 day this week.", isSummary: true)],
      "the fallback totals line keeps its text and is the quieter summary")
let older = InsightsText.patterns(nil, observations: ["You completed 2 activities this week."])
check(older == [.init(heading: nil, body: "You completed 2 activities this week.", isSummary: false)],
      "older backend: its sentences, as they are")
check(InsightsText.patterns(nil, observations: []).isEmpty && InsightsText.patterns([], observations: []).isEmpty,
      "nothing to show: the empty-state text")

// The short line for every pattern the backend can send, week and month.
let short = { (h: String?, week: Bool) in InsightsText.shortLine(heading: h, body: "(backend text)", isWeek: week) }
check(short("Finding comfort in your own company", false) == "Solo time seemed to help this month.", "solo (month)")
check(short("Connection seems to help", true) == "Social connection seemed to help this week.", "social (week)")
check(short("Getting outside seems to help", true) == "Getting outside seemed to help this week.", "outdoor")
check(short("Slowing down seems to help", false) == "Slowing down seemed to help this month.", "rest")
check(short("Some days are still harder than others", false) == "Some days were still harder than others this month.", "harder days")
check(short("Your urge to reach out eased", true) == "Your urge to reach out eased this week.", "urge eased")
check(short("Your urge stayed fairly steady", true) == "Your urge stayed fairly steady this week.", "urge steady")
check(short("Urges can rise and fall", true) == "Your urge rose later this week, and that\u{2019}s okay.", "urge higher: no judgement")
check(short("Still finding what fits", false) == "How you felt after activities was mixed this month.", "mixed results")
check(short("Not every activity fits every day", true) == "Not every activity fit this week, and that\u{2019}s okay.", "not better")
check(short("Creative Arts seems to help", true) == "Creative Arts seemed to help this week.", "a future category")
check(short("Something new", true) == "(backend text)", "unknown heading: the backend's own sentence")
check(short(nil, true) == "(backend text)", "no heading (totals): the backend's own sentence")

// At most three patterns: the urge pattern always, then categories; the
// totals line only when there is no category or urge pattern at all.
typealias Item = (kind: String, heading: String?, body: String)
let solo: Item = (kind: "category", heading: "Finding comfort in your own company", body: "solo")
let social: Item = (kind: "category", heading: "Connection seems to help", body: "social")
let outdoor: Item = (kind: "category", heading: "Getting outside seems to help", body: "outdoor")
let rest: Item = (kind: "category", heading: "Slowing down seems to help", body: "rest")
let urge: Item = (kind: "urge", heading: "Some days are still harder than others", body: "urge")
let totals: Item = (kind: "summary", heading: nil, body: "You checked in on 8 days and completed 5 activities this month.")
let lines = { (items: [Item]) in InsightsText.patterns(items, observations: items.map(\.body), isWeek: false).map(\.body) }
check(lines([solo, social, urge, totals]) == ["Solo time seemed to help this month.", "Social connection seemed to help this month.",
                                              "Some days were still harder than others this month."],
      "Karla's month: three short lines, no totals")
check(InsightsText.patterns([urge, totals], observations: [], isWeek: true).map(\.body) == ["Some days were still harder than others this week."],
      "Karla's week: one short line")
check(lines([outdoor, rest, solo, social, urge, totals]) == ["Getting outside seemed to help this month.", "Slowing down seemed to help this month.",
                                                            "Some days were still harder than others this month."],
      "four strong categories: the urge pattern still gets a place; never more than three")
check(lines([outdoor, rest, solo, social, totals]).count == 3 && !lines([outdoor, rest, solo, social, totals]).contains(totals.body),
      "no urge pattern: three categories, no totals")
check(lines([totals]) == [totals.body], "no meaningful pattern at all: the totals line as the neutral fallback")
check(lines([solo, totals]) == ["Solo time seemed to help this month."], "one category pattern: no totals line")
check(InsightsText.patterns(nil, observations: ["a", "b", "c", "d", "e"]).count == 3, "older backend: at most three sentences")
check(InsightsText.patterns([solo, social, urge], observations: []).allSatisfy { $0.heading == nil }, "no bold headings anywhere")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("InsightsText: all passed")
