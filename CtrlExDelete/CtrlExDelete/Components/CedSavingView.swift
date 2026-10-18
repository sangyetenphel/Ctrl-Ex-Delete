import SwiftUI

/// Ced's transition after "Add to my scrapbook": saving, then a short
/// success message on the way to Story.
struct CedSavingView: View {
    enum State: Equatable {
        case saving          // the request is still out
        case saved           // saved; Story is loading
        case storyNotLoaded  // saved, but Story couldn't be refreshed
    }

    let state: State
    /// Loads Story again (never saves again).
    let onRetry: () -> Void
    /// Opens Story with what the app already has.
    let onOpenStory: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var isFloating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Ced floats gently, like in the healing room.
            GhostView(size: 110)
                .offset(y: isFloating ? -6 : 0)
                .padding(.bottom, 28)
                .accessibilityHidden(true)

            if state == .saving {
                ProgressView()
                    .tint(CEDColor.primary)
                    .padding(.bottom, 12)
                Text("Saving your memory\u{2026}")
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.mutedForeground)
            } else {
                Text("You showed up.")
                    .cedTextStyle(.screenTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                Text("One small step deserves a place in your story.")
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if state == .storyNotLoaded {
                VStack(spacing: 12) {
                    Text("Your memory is saved, but your story couldn\u{2019}t be loaded just now.")
                        .cedTextStyle(.body)
                        .foregroundStyle(CEDColor.rose)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Try again", action: onRetry)
                    Button("Open my story", action: onOpenStory)
                        .cedTextStyle(.bodySemibold)
                        .foregroundStyle(CEDColor.mutedForeground)
                }
                .padding(.top, 28)
            }

            Spacer(minLength: 24)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CEDColor.background)
        .animation(.easeInOut(duration: 0.3), value: state)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    CedSavingView(state: .saved, onRetry: {}, onOpenStory: {})
}
