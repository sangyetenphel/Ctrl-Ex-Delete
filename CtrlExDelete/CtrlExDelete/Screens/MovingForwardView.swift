import SwiftUI

/// "Do you feel ready to close this chapter?": reflection questions to tick,
/// then a choice between "not ready yet" (back to the room) and "ready"
/// (on to the final keepsake screen).
struct MovingForwardView: View {
    @Environment(AppRouter.self) private var router
    @State private var checkedQuestions: Set<Int> = []
    @State private var choice: Choice?

    private enum Choice { case notReady, ready }

    private let questions = [
        "Can you think about the relationship without feeling overwhelmed?",
        "Are you building routines that don\u{2019}t include your ex?",
        "Has the urge to contact them become manageable?",
        "Do you feel more connected to yourself?",
        "Are you choosing to move forward because you feel ready\u{2014}not pressured?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Reflect on these questions:").questionLabelStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(questions.indices, id: \.self) { index in
                            questionRow(index)
                        }
                    }

                    VStack(spacing: 12) {
                        choiceCard(.notReady,
                                   label: "I\u{2019}m not ready yet",
                                   detail: "That\u{2019}s okay. Keep going at your own pace.",
                                   textColor: CEDColor.foreground,
                                   selectedFill: CEDColor.card,
                                   selectedBorder: CEDColor.border)
                        choiceCard(.ready,
                                   label: "I\u{2019}m ready to move forward",
                                   detail: "This is a meaningful moment.",
                                   textColor: CEDColor.primary,
                                   selectedFill: CEDColor.secondary,
                                   selectedBorder: CEDColor.primary)
                    }
                    .padding(.top, 8)
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

    private func questionRow(_ index: Int) -> some View {
        let isChecked = checkedQuestions.contains(index)
        return Button {
            if isChecked {
                checkedQuestions.remove(index)
            } else {
                checkedQuestions.insert(index)
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

                Text(questions[index])
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
                            selectedFill: Color, selectedBorder: Color) -> some View {
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
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Shows the choice for half a second, then moves on, like the prototype.
    private func choose(_ option: Choice) {
        guard choice == nil else { return } // ignore a second tap while moving on
        withAnimation(.easeOut(duration: 0.15)) { choice = option }
        Task {
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
