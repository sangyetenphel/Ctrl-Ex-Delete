import SwiftUI

/// Activity recommendations: one card at a time with arrows and dots to page
/// through, plus Skip, "I'll try this" and Save buttons.
struct ActivitiesView: View {
    @Environment(AppRouter.self) private var router
    @State private var deck = ActivityDeck()
    @State private var isToastVisible = false
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    ActivityCard(
                        activity: deck.current,
                        canGoBack: deck.canGoBack,
                        canGoForward: deck.canGoForward,
                        onBack: { deck.goBack() },
                        onForward: { deck.goForward() }
                    )
                    .padding(.bottom, 20)

                    pageDots
                        .padding(.bottom, 20)

                    actionButtons
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CEDColor.background)
        .overlay(alignment: .bottom) {
            if isToastVisible {
                ToastView(message: "Saved for another day")
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Day 1")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow)
                .foregroundStyle(CEDColor.primary)
                .padding(.bottom, 4)

            Text("Today seems a little heavy.")
                .cedTextStyle(.pageTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("Pick something that feels doable.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: Dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(deck.activities.indices, id: \.self) { index in
                Button {
                    deck.go(to: index)
                } label: {
                    Circle()
                        .fill(index == deck.index ? CEDColor.primary : CEDColor.border)
                        .frame(width: 8, height: 8)
                        // Bigger invisible tap area without changing the spacing.
                        .padding(8)
                        .contentShape(Rectangle())
                        .padding(-8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Activity \(index + 1) of \(deck.activities.count)")
                .accessibilityAddTraits(index == deck.index ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Skip / I'll try this / Save

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                deck.goForward()
            } label: {
                HStack(spacing: 6) {
                    CEDIconView(icon: .xMark, size: 22, color: CEDColor.mutedForeground)
                    Text("Skip")
                }
                .actionButtonLabel(textColor: CEDColor.mutedForeground, borderColor: CEDColor.border)
            }
            .buttonStyle(.plain)

            Button {
                router.go(to: .reflection)
            } label: {
                Text("I\u{2019}ll try this")
                    .cedTextStyle(.bodyBold)
                    .foregroundStyle(CEDColor.cream)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 14)
                    .background(CEDColor.primary, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
            }
            .buttonStyle(PressScaleButtonStyle())

            Button(action: saveCurrentActivity) {
                HStack(spacing: 4) {
                    CEDIconView(
                        icon: deck.isCurrentSaved ? .bookmarkFilled : .bookmark,
                        size: 22,
                        color: CEDColor.accent
                    )
                    Text(deck.isCurrentSaved ? "Saved" : "Save")
                }
                .actionButtonLabel(
                    textColor: deck.isCurrentSaved ? CEDColor.accent : CEDColor.mutedForeground,
                    borderColor: deck.isCurrentSaved ? CEDColor.accent : CEDColor.border
                )
            }
            .buttonStyle(.plain)
        }
        // All three buttons share the height of the tallest one.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveCurrentActivity() {
        // Like the prototype, saving the same card again does nothing.
        guard deck.saveCurrent() else { return }

        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { isToastVisible = true }
        AccessibilityNotification.Announcement("Saved for another day").post()

        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { isToastVisible = false }
        }
    }
}

// MARK: - Activity card

/// The rounded card: tinted art area with the icon, category pill and arrows,
/// then a white section with the title, instructions and "Why this fits today".
private struct ActivityCard: View {
    let activity: Activity
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            artArea
            details
        }
        .background(activity.background)
        .clipShape(RoundedRectangle(cornerRadius: CEDRadius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: CEDRadius.xxl)
                .strokeBorder(CEDColor.border, lineWidth: 1)
        )
    }

    private var artArea: some View {
        VStack(spacing: 8) {
            CEDIconView(icon: activity.icon, size: 32, color: activity.accent)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: CEDRadius.xl))

            Text(activity.category)
                .cedTextStyle(.captionBold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(activity.accent, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .background(activity.background)
        .overlay(alignment: .leading) {
            arrowButton(icon: .chevronLeft, label: "Previous activity", isEnabled: canGoBack, action: onBack)
                .padding(.leading, 12)
        }
        .overlay(alignment: .trailing) {
            arrowButton(icon: .chevronRight, label: "Next activity", isEnabled: canGoForward, action: onForward)
                .padding(.trailing, 12)
        }
    }

    private func arrowButton(icon: CEDIcon, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CEDIconView(icon: icon, size: 20, color: CEDColor.foreground)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.7), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(activity.title)
                .cedTextStyle(.cardTitle)
                .foregroundStyle(CEDColor.foreground)
                .padding(.bottom, 8)

            Text(activity.instructions)
                .cedTextStyle(.bodyRelaxed)
                .foregroundStyle(CEDColor.foreground)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text("Why this fits today")
                    .textCase(.uppercase)
                    .cedTextStyle(.captionBold.tracking(0.6))
                    .foregroundStyle(CEDColor.primary)
                Text(activity.whyItFits)
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.foreground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(CEDColor.secondary, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(CEDColor.card)
    }
}

// MARK: - Shared look for the Skip and Save buttons

private extension View {
    func actionButtonLabel(textColor: Color, borderColor: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: CEDRadius.xl)
        return self
            .cedTextStyle(.bodyBold)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 14)
            .background(CEDColor.card, in: shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: 2))
            .contentShape(shape)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ActivitiesView()
        .environment(AppRouter())
}
