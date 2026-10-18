import SwiftUI

/// The root of the app. It shows whichever screen the router says is current,
/// plus the bottom tab bar on screens that use it.
struct ContentView: View {
    #if DEBUG
    @State private var router = AppRouter(start: AppRouter.debugStartScreen() ?? .launch)
    #else
    @State private var router = AppRouter()
    #endif
    @State private var journey = JourneyStore()
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

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
        .environment(session)
        // Startup, including after a force-close: ask the backend whether
        // today's check-in exists and reload the activity in progress,
        // memories and day count, then pick the screen (LaunchView meanwhile).
        .task {
            #if DEBUG
            if AppRouter.debugStartScreen() != nil {
                session.skipRestore()
                await journey.refresh()
                return
            }
            #endif
            await session.start(journey: journey, router: router)
        }
        // Back from the background on a new local day: that day's check-in.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.returnedToForeground(journey: journey, router: router) }
            }
        }
        // The prototype is designed for light mode only. The healing room asks
        // for dark so the status bar text turns white over its teal header.
        .preferredColorScheme(router.current == .room ? .dark : .light)
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.current {
        case .launch:
            LaunchView()
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
