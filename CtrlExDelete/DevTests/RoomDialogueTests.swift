// Tests for RoomDialogue (Models/RoomDialogue.swift): when Ced's room card
// invites the user to try an activity. Run with ./DevTests/run.sh.
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition { print("  ok    \(message)") } else { failures += 1; print("  FAIL  \(message) (line \(line))") }
}

let today = "2026-11-08", yesterday = "2026-11-07"
let neutral = "One small step at a time."
func line(text: String? = "You showed up today.", date: String? = today, checkIn: Bool = true,
          completed: Bool?) -> RoomDialogue.Line {
    RoomDialogue.line(messageText: text, messageDate: date, isCheckInMessage: checkIn,
                      activityCompletedToday: completed, today: today, neutralText: neutral)
}

check(line(completed: false) == .init(text: RoomDialogue.invitation, isInvitation: true),
      "checked in today, no activity completed: the invitation (tappable)")
check(RoomDialogue.invitation == "Let\u{2019}s try something small together.", "the invitation's exact words")
check(line(completed: true) == .init(text: "You showed up today.", isInvitation: false),
      "an activity completed today: the day's own message again")
check(line(completed: nil) == .init(text: "You showed up today.", isInvitation: false),
      "completions not known yet (loading, offline, older backend): never the invitation")
check(line(text: "Good to see you. Want to start with a quick check-in?", checkIn: false, completed: false)
      == .init(text: RoomDialogue.welcomeBack, isInvitation: false),
      "the backend's \"let's check in\" line: a welcome instead (never asks to check in twice), not the invitation")
check(RoomDialogue.welcomeBack == "Welcome back. Take your time, this space is yours.", "the welcome's exact words")
check(line(text: "That pull can feel strong.", checkIn: true, completed: true).text == "That pull can feel strong.",
      "after a check-in and an activity: the day's personal message is unchanged")
check(line(date: yesterday, completed: false) == .init(text: neutral, isInvitation: false),
      "yesterday's message is never shown, nor its invitation")
check(line(text: nil, date: nil, completed: nil).text == neutral, "nothing saved: the neutral line")

// Keeping what's known when the message is saved again.
check(RoomDialogue.completedToday(newCount: 0, savedDate: nil, savedValue: nil, date: today) == false,
      "new day's check-in with 0 completed: invitation")
check(RoomDialogue.completedToday(newCount: 2, savedDate: nil, savedValue: nil, date: today) == true,
      "completed earlier today (e.g. before checking in): no invitation")
check(RoomDialogue.completedToday(newCount: nil, savedDate: today, savedValue: false, date: today) == false,
      "no count in a later response: today's knowledge stays")
check(RoomDialogue.completedToday(newCount: 0, savedDate: today, savedValue: true, date: today) == true,
      "a completion seen on this phone today is never undone by a stale response")
check(RoomDialogue.completedToday(newCount: nil, savedDate: yesterday, savedValue: true, date: today) == nil,
      "yesterday's completion doesn't count for today (unknown until the backend says)")
check(RoomDialogue.completedToday(newCount: 0, savedDate: yesterday, savedValue: true, date: today) == false,
      "completed yesterday, new day: the invitation comes back")

if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("All RoomDialogue tests passed.")
