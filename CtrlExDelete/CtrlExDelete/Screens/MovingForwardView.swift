import SwiftUI

/// "Do you feel ready to close this chapter?": five readiness questions, then
/// a choice. "I'm not ready yet" is always available and goes back to the
/// room (nothing saved). "I'm ready to move forward" only works once all five
/// are ticked; it saves the readiness (the backend checks the same rule) and
/// opens the farewell gift, which makes a fresh scrapbook every time.
/// Every visit starts with nothing ticked. Nothing is deleted or locked.
struct MovingForwardView: View {
    @Environment(AppRouter.self) private var router
    @State private var checkedQuestions: Set<MovingForwardQuestion> = []
    @State private var choice: Choice?
    @State private var saveError: String?

    private enum Choice { case notReady, ready }

    private var isReadyEnabled: Bool {
        checkedQuestions.count == MovingForwardQuestion.allCases.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Reflect on these questions:").questionLabelStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(MovingForwardQuestion.allCases) { question in
                            questionRow(question)
                        }
                    }
                    .disabled(choice != nil)   // fixed while the choice is being saved

                    VStack(spacing: 12) {
                        choiceCard(.notReady,
                                   label: "I\u{2019}m not ready yet",
                                   detail: "That\u{2019}s okay. Keep going at your own pace.",
                                   textColor: CEDColor.foreground,
                                   selectedFill: CEDColor.card,
                                   selectedBorder: CEDColor.border)
                        choiceCard(.ready,
                                   label: "I\u{2019}m ready to move forward",
                                   detail: isReadyEnabled ? "This is a meaningful moment."
                                       : "Tick all five questions when they feel true for you.",
                                   textColor: CEDColor.primary,
                                   selectedFill: CEDColor.secondary,
                                   selectedBorder: CEDColor.primary,
                                   isEnabled: isReadyEnabled)
                    }
                    .padding(.top, 8)

                    if let saveError {
                        Text(saveError)
                            .cedTextStyle(.body)
                            .foregroundStyle(CEDColor.rose)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(CEDColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconBadge {
                GhostView(size: 28)
            }
            .padding(.bottom, 12)

            Text("Do you feel ready to close this chapter?")
                .cedTextStyle(.pageTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("There\u{2019}s no right answer. Take your time.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 8)
        }
        .cardHeaderStyle()
    }

    private func questionRow(_ question: MovingForwardQuestion) -> some View {
        let isChecked = checkedQuestions.contains(question)
        return Button {
            if isChecked {
                checkedQuestions.remove(question)
            } else {
                checkedQuestions.insert(question)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isChecked ? CEDColor.secondary : .clear)
                    .overlay(Circle().strokeBorder(isChecked ? CEDColor.primary : CEDColor.border, lineWidth: 2))
                    .overlay {
                        if isChecked {
                            CEDIconView(icon: .check, size: 20, color: CEDColor.primary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)

                Text(question.text)
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isChecked)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private func choiceCard(_ option: Choice, label: String, detail: String, textColor: Color,
                            selectedFill: Color, selectedBorder: Color, isEnabled: Bool = true) -> some View {
        let isSelected = choice == option
        let shape = RoundedRectangle(cornerRadius: CEDRadius.xl)
        return Button {
            choose(option)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .cedTextStyle(.bodyBold)
                    .foregroundStyle(textColor)
                Text(detail)
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(isSelected ? selectedFill : CEDColor.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? selectedBorder : CEDColor.border, lineWidth: 2))
            .contentShape(shape)
            // Faded while it can't be chosen yet.
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isEnabled ? "" : "Available once all five questions are ticked.")
    }

    /// "Not ready" shows the choice briefly and goes back to the room
    /// (nothing saved). "Ready" (only with all five ticked) saves first and
    /// moves on once the backend confirms; a failure stays here, ticks intact.
    private func choose(_ option: Choice) {
        guard choice == nil else { return } // ignore a second tap while moving on
        guard option == .notReady || isReadyEnabled else { return }
        saveError = nil
        withAnimation(.easeOut(duration: 0.15)) { choice = option }
        Task {
            if option == .ready {
                let request = MovingForwardRequest(
                    reflectedOn: MovingForwardQuestion.allCases,
                    localDate: LocalDate.text()
                )
                do {
                    _ = try await APIClient.shared.saveMovingForward(request)
                } catch {
                    saveError = "Your choice wasn\u{2019}t saved. \(error.localizedDescription)"
                    withAnimation(.easeOut(duration: 0.15)) { choice = nil }
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            router.go(to: option == .ready ? .finalGift : .room)
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    MovingForwardView()
        .environment(AppRouter(start: .movingForward))
}
