// Tests for StoryText (Models/StoryText.swift): the Story header and the
// memories grouped by month. Run with ./DevTests/run.sh.
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition { print("  ok    \(message)") } else { failures += 1; print("  FAIL  \(message) (line \(line))") }
}

check(StoryText.memoriesCollected(9) == "9 memories collected", "header: 9")
check(StoryText.memoriesCollected(10) == "10 memories collected", "header: 10 after the demo's reflection")
check(StoryText.memoriesCollected(1) == "1 memory collected", "header: singular")
check(StoryText.memoriesCollected(0) == "0 memories collected", "header: none yet")

// A journey like Karla's, newest first (the order the app keeps memories in).
let karla: [(id: Int, localDate: String)] = [
    (9, "2026-11-11"), (8, "2026-11-09"), (7, "2026-11-08"), (6, "2026-11-05"), (5, "2026-11-03"),
    (4, "2026-10-31"), (3, "2026-10-29"), (2, "2026-10-27"), (1, "2026-10-25"),
]
check(StoryText.byMonth(karla) == [
        .init(title: "November 2026", ids: [9, 8, 7, 6, 5]),
        .init(title: "October 2026", ids: [4, 3, 2, 1])],
      "two months, newest first, each in the order given")
check(StoryText.byMonth([(10, "2026-11-13")] + karla).first == .init(title: "November 2026", ids: [10, 9, 8, 7, 6, 5]),
      "the demo's 10th memory joins November at the front")
check(StoryText.byMonth([]).isEmpty, "no memories: no groups")
check(StoryText.byMonth([(1, "2027-01-02"), (2, "2026-12-30")]).map(\.title) == ["January 2027", "December 2026"],
      "across a year boundary, newest first")
check(StoryText.byMonth([(1, "2026-09-10"), (2, "2026-11-01")]).map(\.title) == ["November 2026", "September 2026"],
      "months with no memories (October) simply don't appear")
check(StoryText.byMonth([(1, "2026-11-02"), (2, "not a date")]) == [
        .init(title: "November 2026", ids: [1]), .init(title: "Earlier", ids: [2])],
      "an unreadable date goes last, under Earlier (never lost)")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("StoryText: all passed")
