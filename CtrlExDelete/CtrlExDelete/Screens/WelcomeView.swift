import SwiftUI

/// Opening screen: Ced's logo, the app name and the button that starts today's check-in.
struct WelcomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Text("your healing space")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow.tracking(3))
                .foregroundStyle(CEDColor.accent)

            Spacer(minLength: 24)

            VStack(spacing: 32) {
                GhostView(size: 110)

                VStack(spacing: 0) {
                    Text("Ctrl+Ex+Delete")
                        .cedTextStyle(.welcomeTitle)
                        .foregroundStyle(CEDColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)

                    Rectangle()
                        .fill(CEDColor.primary)
                        .frame(width: 56, height: 2)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    Text("A private space to process the breakup, interrupt old patterns, and take small steps toward yourself again.")
                        .cedTextStyle(.bodyRelaxed)
                        .foregroundStyle(CEDColor.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 270)
                }
            }
            // The prototype nudges this group 24pt upward (`-mt-6`).
            .padding(.top, -24)

            Spacer(minLength: 24)

            PrimaryButton(title: "Begin today\u{2019}s check-in", enabledTextColor: .white) {
                router.go(to: .checkIn)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            WelcomeBackground()
        }
    }
}

/// The three soft circles that peek in from the screen edges.
private struct WelcomeBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                CEDColor.background

                Circle()
                    .fill(CEDColor.accent.opacity(0.2))
                    .frame(width: 224, height: 224)
                    .position(x: size.width - 32, y: 32)

                Circle()
                    .fill(CEDColor.secondary.opacity(0.1))
                    .frame(width: 288, height: 288)
                    .position(x: 48, y: size.height - 32)

                Circle()
                    .fill(CEDColor.peach.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .position(x: size.width - 24, y: size.height / 2 + 80)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    WelcomeView()
        .environment(AppRouter())
}
