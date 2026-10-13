import SwiftUI

/// Every screen in the prototype, in the order of the Figma Make flow.
enum AppScreen: String, CaseIterable {
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

    /// The welcome and check-in screens are full screen; the rest show the tab bar.
    var showsBottomNav: Bool {
        self != .welcome && self != .checkIn
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

    init(start: AppScreen = .welcome) {
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
    static func debugStartScreen() -> AppScreen {
        let name = UserDefaults.standard.string(forKey: "CEDStartScreen") ?? ""
        return AppScreen(rawValue: name) ?? .welcome
    }
    #endif
}
