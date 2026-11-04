import Foundation

// A conversation with Ced. Replies come from the backend (POST /ced/messages);
// the conversation lives only in memory while the chat is open and is
// discarded when the user ends it. Nothing is sent to the user's ex.

struct ChatMessage: Identifiable, Equatable {
    enum Sender { case user, ced }

    let id = UUID()
    let sender: Sender
    let text: String
    /// Crisis resources shown right under this bubble (the last of a reply).
    var support: CrisisSupport? = nil
}

enum CedChat {
    /// Placeholder on the Talk screen's unsent-message box.
    static let unsentMessagePlaceholder = "I miss you, and I want to know if you miss me too."

    /// Ced's greeting when the chat opens without an unsent message.
    static let greeting = "I\u{2019}m here. What\u{2019}s on your mind right now?"

    /// How many recent messages the app sends; the server trims further.
    static let maxMessagesSent = 20

    /// The server's limit for one turn. A longer one (a long unsent letter,
    /// or several bubbles merged into one turn) would be refused, and with
    /// it every later message, so each turn keeps its latest characters.
    static let maxCharactersPerTurn = 2000

    /// The request for Ced's next reply. `startedFromUnsentMessage`: the first
    /// message was written on "Say it here first" (words for the ex, not sent).
    static func request(for messages: [ChatMessage], startedFromUnsentMessage: Bool) -> CedChatRequest {
        // One reply shown as several bubbles is one turn for the AI.
        var turns: [CedChatRequest.Turn] = []
        for message in messages {
            let role = message.sender == .user ? "user" : "assistant"
            if let last = turns.last, last.role == role {
                turns[turns.count - 1] = .init(role: role, content: last.content + "\n\n" + message.text)
            } else {
                turns.append(.init(role: role, content: message.text))
            }
        }
        let recent = turns.suffix(maxMessagesSent).map { turn in
            CedChatRequest.Turn(role: turn.role, content: String(turn.content.suffix(maxCharactersPerTurn)))
        }
        return CedChatRequest(
            messages: recent,
            mode: startedFromUnsentMessage && recent.count == turns.count ? "unsent_message" : "chat"
        )
    }
}
