import SwiftUI

/// Shown while the app restores the user's session on startup, and if that
/// fails: a clear connection message with Try again. Progress already on
/// this device stays, and nothing is reset or asked again.
struct LaunchView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            GhostView(size: 96)

            switch session.phase {
            case .failed(let message):
                failure(message)
            case .restoring, .ready:
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(CEDColor.primary)
                    Text("Getting your room ready\u{2026}")
                        .cedTextStyle(.body)
                        .foregroundStyle(CEDColor.mutedForeground)
                    if session.isWakingServer {
                        Text("Waking up the server. This can take up to a minute; your progress is safe.")
                            .cedTextStyle(.caption)
                            .foregroundStyle(CEDColor.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(CEDColor.background.ignoresSafeArea())
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("We can\u{2019}t reach Ctrl+Ex+Delete right now")
                    .cedTextStyle(.cardTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .cedTextStyle(.body)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .multilineTextAlignment(.center)
                Text(savedProgressNote)
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                PrimaryButton(title: "Try again") {
                    Task { await session.start(journey: journey, router: router) }
                }
                if journey.cachedAt != nil {
                    OutlineButton(title: "Continue with saved progress", color: CEDColor.primary) {
                        session.continueWithSavedProgress(router: router)
                    }
                }
            }
        }
    }

    private var savedProgressNote: String {
        guard let cachedAt = journey.cachedAt else {
            return "Your progress is safe. Nothing has been reset."
        }
        let when = cachedAt.formatted(.relative(presentation: .named))
        return "Your progress is safe. This phone last updated it \(when), and will again once we reconnect."
    }
}
