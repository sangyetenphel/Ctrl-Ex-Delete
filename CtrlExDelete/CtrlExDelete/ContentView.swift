import SwiftUI

/// The root of the app. It shows whichever screen the router says is current,
/// plus the bottom tab bar on screens that use it.
struct ContentView: View {
    #if DEBUG
    @State private var router = AppRouter(start: AppRouter.debugStartScreen())
    #else
    @State private var router = AppRouter()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .id(router.current)

            if router.current.showsBottomNav {
                BottomNavBar()
            }
        }
        .environment(router)
        // The prototype is designed for light mode only.
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.current {
        case .welcome:
            WelcomeView()
        case .checkIn:
            CheckInView()
        case .activities:
            ActivitiesView()
        case .scrapbook:
            ScrapbookView()
        default:
            UpcomingScreen(screen: router.current)
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ContentView()
}
