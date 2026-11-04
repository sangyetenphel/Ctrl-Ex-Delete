import SwiftUI

@main struct MyApp: App {
    init() {
        FontRegistrar.registerBundledFonts()
        #if DEBUG
        APIConfig.logActiveBackend()
        // Only with the Xcode launch argument -CEDClearLocalJourneyCache (once per value).
        LocalJourneyCacheReset.runAtLaunch()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
