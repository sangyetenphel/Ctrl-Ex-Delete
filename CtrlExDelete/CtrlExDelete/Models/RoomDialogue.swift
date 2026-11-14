import Foundation

/// What Ced says in the healing room's card. Foundation only, so the rule can
/// be tested on the Mac (DevTests/RoomDialogueTests.swift).
///
/// After today's check-in, until the user has completed an activity today
/// (their own local calendar day), Ced invites them to try one. Otherwise it's
/// the day's message from the backend, except the backend's "let's check in"
/// line, which becomes a welcome (the app asks for the check-in first). While today's completions
/// aren't known (loading, no connection, an older backend) the invitation is
/// never shown: the day's message stays.
enum RoomDialogue {
    static let invitation = "Let\u{2019}s try something small together."
    /// Shown instead of the backend's "let's check in" line, so the room
    /// never asks for a second check-in.
    static let welcomeBack = "Welcome back. Take your time, this space is yours."

    struct Line: Equatable {
        let text: String
        /// Tapping the card leads to today's activity recommendations.
        let isInvitation: Bool
    }

    /// - Parameters:
    ///   - messageText/messageDate: the saved room message and its local day, if any.
    ///   - isCheckInMessage: the message belongs to a check-in (not "let's check in").
    ///   - activityCompletedToday: nil while unknown.
    static func line(messageText: String?, messageDate: String?, isCheckInMessage: Bool,
                     activityCompletedToday: Bool?, today: String, neutralText: String) -> Line {
        guard let messageText, messageDate == today else { return Line(text: neutralText, isInvitation: false) }
        // Today's message isn't from a check-in: it's the backend's "want to
        // start with a quick check-in?". The check-in comes before the room in
        // the app, so Ced welcomes the user instead of asking again.
        guard isCheckInMessage else { return Line(text: welcomeBack, isInvitation: false) }
        if activityCompletedToday == false {
            return Line(text: invitation, isInvitation: true)
        }
        return Line(text: messageText, isInvitation: false)
    }

    /// Keeps what's known about today's completions when a message is saved
    /// again: a new count wins; without one, the same day's knowledge stays;
    /// a completion seen on this phone today is never undone.
    static func completedToday(newCount: Int?, savedDate: String?, savedValue: Bool?, date: String) -> Bool? {
        let saved = savedDate == date ? savedValue : nil
        if saved == true { return true }
        if let newCount { return newCount > 0 }
        return saved
    }
}
