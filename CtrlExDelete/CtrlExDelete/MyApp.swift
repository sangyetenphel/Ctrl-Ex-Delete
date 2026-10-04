import SwiftUI

@main struct MyApp: App {
    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
