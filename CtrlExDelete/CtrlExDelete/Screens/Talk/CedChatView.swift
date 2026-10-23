import SwiftUI

/// The conversation with Ced. Replies come from the backend (and from there
/// the AI provider). The conversation exists only in this view's memory:
/// closing the chat discards it, and the server never stores it.
struct CedChatView: View {
    let initialMessage: String
    let onClose: () -> Void

    @Environment(AppRouter.self) private var router
    @State private var messages: [ChatMessage]
    @State private var reply = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @State private var replyTask: Task<Void, Never>?

    /// The chat began with words written for the ex on "Say it here first".
    private let startedFromUnsentMessage: Bool
    private let bottomID = "bottom"

    init(initialMessage: String, onClose: @escaping () -> Void) {
        self.initialMessage = initialMessage
        self.onClose = onClose
        let unsent = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        startedFromUnsentMessage = !unsent.isEmpty
        _messages = State(initialValue: unsent.isEmpty
            ? [ChatMessage(sender: .ced, text: CedChat.greeting)]
            : [ChatMessage(sender: .user, text: unsent)])
    }

    private var canSend: Bool {
        !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            composer
        }
        .background(CEDColor.background)
        .task {
            // Ced answers the unsent message as soon as the chat opens.
            if messages.last?.sender == .user { requestReply() }
        }
        .onDisappear { replyTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            CedAvatar(size: 38)

            VStack(alignment: .leading, spacing: 0) {
                Text("Talk with Ced")
                    .cedTextStyle(CEDTextStyle(font: .loraBold, size: 16, lineHeight: 20, relativeTo: .headline))
                    .foregroundStyle(CEDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text("Here with you")
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
                Text("Ced is an AI companion for reflection, not a therapist. Messages do not provide diagnosis or treatment, or guarantee recovery.")
                    .cedTextStyle(.smallSnug)
                    .foregroundStyle(CEDColor.hint)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                Button("Get human support") {
                    withAnimation(.easeOut(duration: 0.25)) {
                        router.isSupportSheetPresented = true
                    }
                }
                .cedTextStyle(.smallSemibold)
                .foregroundStyle(CEDColor.primary)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CircleIconButton(icon: .xMark, iconSize: 18, iconColor: CEDColor.mutedForeground,
                             label: "End conversation and return to room", action: onClose)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(CEDColor.card.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CEDColor.border).frame(height: 1)
        }
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(messages.indices, id: \.self) { index in
                        messageRow(at: index)
                    }
                    if isThinking {
                        CedBubble(showsName: messages.last?.sender != .ced) { ThinkingDots() }
                            .accessibilityLabel("Ced is typing")
                            .padding(.top, messages.last?.sender == .ced ? 4 : 12)
                    }
                    if let errorMessage {
                        errorRow(errorMessage)
                            .padding(.top, 12)
                    }
                    Color.clear.frame(height: 0).id(bottomID)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages) { scrollToBottom(proxy) }
            .onChange(of: isThinking) { scrollToBottom(proxy) }
            .onChange(of: errorMessage) { scrollToBottom(proxy) }
        }
    }

    /// Ced's bubbles from one reply sit close together like a messaging app:
    /// "Ced" over the first, the avatar beside the last. Crisis resources
    /// appear right under the bubble they belong to.
    @ViewBuilder
    private func messageRow(at index: Int) -> some View {
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1].sender : nil
        let next = index + 1 < messages.count ? messages[index + 1].sender : nil
        let continuesGroup = previous == message.sender

        VStack(spacing: 8) {
            switch message.sender {
            case .user:
                UserBubble(text: message.text)
            case .ced:
                CedBubble(showsName: !continuesGroup,
                          showsAvatar: next != .ced && !(index == messages.count - 1 && isThinking)) {
                    Text(message.text)
                }
            }
            if let support = message.support {
                CrisisSupportCard(support: support) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        router.isSupportSheetPresented = true
                    }
                }
            }
        }
        .padding(.top, index == 0 ? 0 : (continuesGroup ? 4 : 12))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 8) {
            // Starts a voice call with Ced; this text chat stays as it is.
            CallCedButton()

            TextField("", text: $reply, prompt: Text("Reply to Ced\u{2026}").foregroundStyle(CEDColor.foreground.opacity(0.5)))
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.foreground)
                .tint(CEDColor.primary)
                .submitLabel(.send)
                .onSubmit(sendReply)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(CEDColor.background, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
                .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(CEDColor.border, lineWidth: 1))

            CircleIconButton(icon: .send, iconColor: .white,
                             background: canSend ? CEDColor.primary : CEDColor.border,
                             label: "Send reply", action: sendReply)
                .disabled(!canSend)
        }
        .padding(12)
        .background(CEDColor.card)
        .overlay(alignment: .top) {
            Rectangle().fill(CEDColor.border).frame(height: 1)
        }
    }

    /// Couldn't get a reply: say why, and offer to try again.
    private func errorRow(_ message: String) -> some View {
        VStack(spacing: 6) {
            Text(message)
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
            Button("Try again", action: requestReply)
                .cedTextStyle(.captionBold)
                .foregroundStyle(CEDColor.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(sender: .user, text: text))
        reply = ""
        requestReply()
    }

    /// Asks the backend for Ced's reply to the conversation so far.
    private func requestReply() {
        guard !isThinking else { return }
        errorMessage = nil
        isThinking = true
        let request = CedChat.request(for: messages, startedFromUnsentMessage: startedFromUnsentMessage)

        replyTask = Task {
            defer { isThinking = false }
            do {
                let response = try await APIClient.shared.cedReply(request)
                guard !Task.isCancelled else { return }
                AccessibilityNotification.Announcement("Ced: \(response.messages.joined(separator: " "))").post()

                for (index, text) in response.messages.enumerated() {
                    // A short pause between bubbles, like someone texting.
                    // Crisis replies show at once so the resources are there right away.
                    if index > 0, response.support == nil {
                        try? await Task.sleep(for: .milliseconds(650))
                        guard !Task.isCancelled else { return }
                    }
                    let isLast = index == response.messages.count - 1
                    withAnimation(.easeOut(duration: 0.2)) {
                        messages.append(ChatMessage(sender: .ced, text: text,
                                                    support: isLast ? response.support : nil))
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Bubbles

/// The user's messages: dark blue, on the right, with a small top-right corner.
private struct UserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .cedTextStyle(.bodyRelaxed)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                CEDColor.primary,
                in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16,
                                           bottomTrailingRadius: 16, topTrailingRadius: 2)
            )
            .containerRelativeFrame(.horizontal, alignment: .trailing) { width, _ in (width - 32) * 0.78 } // 78% of the padded column
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("You: \(text)")
    }
}

/// Ced's messages: avatar, "Ced" label and a powder-blue bubble on the left.
/// In a run of bubbles, only the first shows "Ced" and only the last the avatar.
private struct CedBubble<Content: View>: View {
    var showsName = true
    var showsAvatar = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CedAvatar(size: 26)
                .padding(.bottom, 2)
                .opacity(showsAvatar ? 1 : 0)
                .accessibilityHidden(!showsAvatar)

            VStack(alignment: .leading, spacing: 2) {
                if showsName {
                    Text("Ced")
                        .cedTextStyle(.smallBold)
                        .foregroundStyle(CEDColor.accent)
                        .padding(.leading, 4)
                }
                content
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.foreground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        CEDColor.secondary,
                        in: UnevenRoundedRectangle(topLeadingRadius: showsName ? 2 : 16, bottomLeadingRadius: 16,
                                                   bottomTrailingRadius: 16, topTrailingRadius: 16)
                    )
            }
            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in (width - 32) * 0.78 } // 78% of the padded column
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Three bouncing dots while Ced is "thinking".
private struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(CEDColor.accent.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .offset(y: reduceMotion ? 0 : Self.bounce(time: time - Double(index) * 0.2))
                }
            }
            .frame(height: 20)
        }
    }

    /// Matches the prototype's keyframes: rise 5pt at 40% of a 1.2s loop, rest from 80%.
    private static func bounce(time: Double) -> CGFloat {
        let progress = (time.truncatingRemainder(dividingBy: 1.2) + 1.2).truncatingRemainder(dividingBy: 1.2) / 1.2
        guard progress < 0.8 else { return 0 }
        return -5 * sin(.pi * progress / 0.8)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    CedChatView(initialMessage: "") {}
        .environment(AppRouter(start: .talk))
}
