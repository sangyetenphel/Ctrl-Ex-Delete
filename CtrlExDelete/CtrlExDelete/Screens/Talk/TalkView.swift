import SwiftUI

/// "Say it here first": write the message you want to send your ex, then
/// send it to Ced in the text chat, or talk it through on a voice call.
struct TalkView: View {
    @Environment(AppRouter.self) private var router
    @State private var message = ""
    @State private var isChatOpen = false
    @State private var isCalling = false

    private static let messageCardID = "unsentMessageCard"

    var body: some View {
        if isChatOpen {
            CedChatView(initialMessage: message) {
                // Ending the conversation discards it (including the unsent
                // message) and returns to the room, like the prototype.
                message = ""
                isChatOpen = false
                router.go(to: .room)
            }
        } else {
            writingView
        }
    }

    private var writingView: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        unsentMessageCard
                            .id(Self.messageCardID)

                        VStack(spacing: 12) {
                            PrimaryButton(title: "Talk it through with Ced", isCompact: true,
                                          systemImage: "phone.fill") {
                                isCalling = true
                            }
                            .accessibilityHint("Starts a voice call with Ced")
                            .fullScreenCover(isPresented: $isCalling) {
                                CallCedView()
                            }

                            Button("Return to my room") {
                                router.go(to: .room)
                            }
                            .cedTextStyle(.bodySemibold)
                            .foregroundStyle(CEDColor.mutedForeground)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // The keyboard leaves little room here: keep the send button in view.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.messageCardID, anchor: .bottom)
                    }
                }
            }
        }
        .background(CEDColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconBadge {
                    GhostView(size: 28)
                }
                Text("Say it here first.")
                    .cedTextStyle(.cardTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 12)

            Text("Write what you want to send them. You can release it without reopening the conversation.")
                .cedTextStyle(.bodyRelaxed)
                .foregroundStyle(CEDColor.mutedForeground)

            HStack(alignment: .top, spacing: 8) {
                CEDIconView(icon: .info, size: 14, color: CEDColor.mutedForeground)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Messages written here are never sent to your ex.")
                        .cedTextStyle(.caption)
                        .foregroundStyle(CEDColor.mutedForeground)
                    Text("Your message will leave this space when you end the conversation.")
                        .cedTextStyle(.caption)
                        .foregroundStyle(CEDColor.hint)
                }
                // Wrap onto more lines instead of cutting the text off.
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CEDColor.secondary, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
            .accessibilityElement(children: .combine)
            .padding(.top, 12)
        }
        .cardHeaderStyle(bottomPadding: 16)
    }

    private var unsentMessageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your unsent message.")
                .cedTextStyle(.serifLabel)
                .foregroundStyle(CEDColor.foreground)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            TextField("", text: $message,
                      prompt: Text(CedChat.unsentMessagePlaceholder).foregroundStyle(CEDColor.hint),
                      axis: .vertical)
                .lineLimit(7, reservesSpace: true)
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.foreground)
                .tint(CEDColor.primary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 56) // room for the send button
                .accessibilityLabel("Your unsent message")
        }
        .background(CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(CEDColor.border, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            CircleIconButton(icon: .send, iconColor: canSend ? CEDColor.primary : CEDColor.hint,
                             label: "Send message", hint: "Opens a text chat with Ced about this message",
                             action: sendMessage)
                .disabled(!canSend)
                .padding(12)
        }
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        guard canSend, !isChatOpen else { return }
        withAnimation(.easeInOut(duration: 0.25)) { isChatOpen = true }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    TalkView()
        .environment(AppRouter(start: .talk))
}
