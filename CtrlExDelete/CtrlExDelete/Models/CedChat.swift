import Foundation

// A conversation with Ced. Replies come from the backend (POST /ced/messages);
// the conversation lives only in memory while the chat is open and is
// discarded when the user ends it. Nothing is sent to the user's ex.

struct ChatMessage: Identifiable, Equatable {
    enum Sender { case user, ced }

    let id = UUID()
    let sender: Sender
    let text: String
}

enum CedChat {
    /// Placeholder on the Talk screen's unsent-message box.
    static let unsentMessagePlaceholder = "I miss you, and I want to know if you miss me too."

    /// Ced's greeting when the chat opens without an unsent message.
    static let greeting = "I\u{2019}m here. What\u{2019}s on your mind right now?"

    /// How many recent messages the app sends; the server trims further.
    static let maxMessagesSent = 20

    /// The request for Ced's next reply. `startedFromUnsentMessage`: the first
    /// message was written on "Say it here first" (words for the ex, not sent).
    static func request(for messages: [ChatMessage], startedFromUnsentMessage: Bool) -> CedChatRequest {
        let recent = messages.suffix(maxMessagesSent)
        return CedChatRequest(
            messages: recent.map { .init(role: $0.sender == .user ? "user" : "assistant", content: $0.text) },
            mode: startedFromUnsentMessage && recent.count == messages.count ? "unsent_message" : "chat"
        )
    }
}
