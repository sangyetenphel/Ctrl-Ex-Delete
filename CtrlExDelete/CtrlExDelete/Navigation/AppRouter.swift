import SwiftUI

/// Every screen in the prototype, in the order of the Figma Make flow.
enum AppScreen: String, CaseIterable {
    /// Restoring the session at startup (or the connection message if that fails).
    case launch
    case welcome
    case checkIn
    case room
    case activities
    case reflection
    case talk
    case scrapbook
    case progress
    case movingForward
    case finalGift
    /// The plant mini game, opened from the room's big plant.
    case growWithKindness

    /// The launch, welcome, check-in and plant-game screens are full screen; the rest show the tab bar.
    var showsBottomNav: Bool {
        self != .launch && self != .welcome && self != .checkIn && self != .growWithKindness
    }
}

/// Keeps track of which screen is showing. Screens read it from the
/// environment and call `go(to:)` to move around the app.
@Observable
final class AppRouter {
    private(set) var current: AppScreen

    /// The "Connect with human support" sheet. It's shown by ContentView so
    /// it can cover the whole screen, including the tab bar.
    var isSupportSheetPresented = false

    init(start: AppScreen = .launch) {
        current = start
    }

    func go(to screen: AppScreen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            current = screen
        }
    }

    #if DEBUG
    /// Lets you open a specific screen when testing, e.g. launch argument
    /// `-CEDStartScreen checkIn` (Product ▸ Scheme ▸ Edit Scheme ▸ Arguments).
    /// nil without the argument: the app restores the session and decides.
    static func debugStartScreen() -> AppScreen? {
        let name = UserDefaults.standard.string(forKey: "CEDStartScreen") ?? ""
        return AppScreen(rawValue: name)
    }
    #endif
}
