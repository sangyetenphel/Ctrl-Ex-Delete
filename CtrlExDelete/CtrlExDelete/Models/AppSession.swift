import SwiftUI

/// Restores the user's session when the app starts (including after a
/// force-close) and when it comes back on a new day, and picks the screen
/// to show. The backend decides; a failed request never counts as "hasn't
/// checked in", and never makes a new user or resets progress.
@Observable
final class AppSession {
    enum Phase: Equatable {
        case restoring
        case failed(String)
        case ready
    }

    private(set) var phase = Phase.restoring
    /// The local day the backend last confirmed the check-in status for.
    private var restoredDay: String?
    private var isRestoring = false

    /// Where a restored user goes: the room if they checked in today, the
    /// daily check-in if not, and the welcome screen if they never have.
    static func startScreen(for status: CheckInStatusDTO) -> AppScreen {
        if status.checkIn != nil { return .room }
        return status.hasAnyCheckIn ? .checkIn : .welcome
    }

    /// App start, and "Try again" on the connection screen.
    func start(journey: JourneyStore, router: AppRouter) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        withAnimation(.easeInOut(duration: 0.2)) { phase = .restoring }

        let today = LocalDate.text()
        do {
            let status = try await journey.restoreSession(today: today)
            restoredDay = today
            phase = .ready
            router.go(to: Self.startScreen(for: status))
        } catch {
            // Keep whatever progress this device saved last time on hand.
            journey.showCachedProgress()
            withAnimation(.easeInOut(duration: 0.2)) { phase = .failed(error.localizedDescription) }
        }
    }

    /// "Continue with saved progress" on the connection screen.
    func continueWithSavedProgress(router: AppRouter) {
        phase = .ready
        router.go(to: .room)
    }

    /// Back in the foreground. On a new local day (or if the start never
    /// reached the backend), checks again and asks for that day's check-in
    /// if there isn't one. Failures here leave the current screen alone.
    func returnedToForeground(journey: JourneyStore, router: AppRouter) async {
        let today = LocalDate.text()
        guard phase == .ready, restoredDay != today, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        guard let status = try? await journey.restoreSession(today: today) else { return }
        restoredDay = today
        // Don't pull someone out of something they're in the middle of.
        let busyScreens: Set<AppScreen> = [.reflection, .checkIn, .welcome, .movingForward, .finalGift]
        if status.checkIn == nil, !busyScreens.contains(router.current) {
            router.go(to: Self.startScreen(for: status))
        }
    }

    #if DEBUG
    /// `-CEDStartScreen` runs skip the startup routing.
    func skipRestore() {
        phase = .ready
        restoredDay = LocalDate.text()
    }
    #endif
}
