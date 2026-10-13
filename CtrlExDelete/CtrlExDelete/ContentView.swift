import SwiftUI

/// The root of the app. It shows whichever screen the router says is current,
/// plus the bottom tab bar on screens that use it.
struct ContentView: View {
    #if DEBUG
    @State private var router = AppRouter(start: AppRouter.debugStartScreen())
    @State private var journey = JourneyStore.debugStore()
    #else
    @State private var router = AppRouter()
    @State private var journey = JourneyStore()
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
        .overlay {
            if router.isSupportSheetPresented {
                SupportSheet()
                    .transition(.opacity)
            }
        }
        // Fills the gaps between screens while they cross-fade.
        .background(CEDColor.background.ignoresSafeArea())
        .environment(router)
        .environment(journey)
        // The prototype is designed for light mode only. The healing room asks
        // for dark so the status bar text turns white over its teal header.
        .preferredColorScheme(router.current == .room ? .dark : .light)
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.current {
        case .welcome:
            WelcomeView()
        case .checkIn:
            CheckInView()
        case .room:
            HealingRoomView()
        case .activities:
            ActivitiesView()
        case .reflection:
            ReflectionView()
        case .scrapbook:
            ScrapbookView()
        case .talk:
            TalkView()
        case .progress:
            ProgressInsightsView()
        case .movingForward:
            MovingForwardView()
        case .finalGift:
            FinalGiftView()
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ContentView()
}
