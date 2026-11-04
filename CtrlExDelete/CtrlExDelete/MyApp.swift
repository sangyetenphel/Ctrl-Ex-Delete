import SwiftUI

@main struct MyApp: App {
    init() {
        FontRegistrar.registerBundledFonts()
        #if DEBUG
        APIConfig.logActiveBackend()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
