import Foundation

// Sample conversation with Ced. These are the prototype's fixed replies:
// there is no real AI here, and nothing is sent anywhere.

struct ChatMessage: Identifiable, Equatable {
    enum Sender { case user, ced }

    let id = UUID()
    let sender: Sender
    let text: String
}

enum CedChat {
    /// The message already written on the Talk screen.
    static let defaultUnsentMessage = "I miss you, and I want to know if you miss me too."

    /// Ced's first reply to the unsent message.
    static let openingReply = "What this message may be reaching for is reassurance that you still matter. Missing someone doesn\u{2019}t mean contacting them will give you the comfort you need. Would you like to wait ten minutes and write what you hope they would say?"

    /// Ced answers each later message with the next one of these, in order.
    static let sampleReplies = [
        "It makes sense to want confirmation that you mattered. But your worth doesn\u{2019}t depend on whether they recognize what they lost. What could remind you of your value tonight without needing an answer from them?",
        "That\u{2019}s a really honest thing to sit with. Sometimes the hardest part isn\u{2019}t missing them \u{2014} it\u{2019}s missing the version of yourself you were in that relationship. What\u{2019}s one thing you\u{2019}ve rediscovered about yourself since?",
        "You\u{2019}re doing something courageous right now by putting it into words instead of sending it. That gap between the urge and the action \u{2014} that\u{2019}s where your healing is happening. How does it feel to hold it here for a moment?",
        "There\u{2019}s no rush to resolve this feeling. Some days it\u{2019}ll be louder, some quieter. Is there something small and grounding you could do in the next hour just for yourself?",
        "You\u{2019}ve shared a lot in this conversation. I want you to know that sitting with these feelings, rather than acting on them, takes real strength. When you\u{2019}re ready, the healing room is a good place to rest.",
    ]

    /// How long Ced "thinks" before replying, like the prototype.
    static let thinkingDelay = Duration.milliseconds(1600)
}
