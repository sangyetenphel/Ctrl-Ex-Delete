// xcode: set sdk=iOS

import Foundation

/// The one place that decides which backend the app talks to.
///
/// - Debug builds (running from Xcode) use the FastAPI server on this Mac.
///   The iOS Simulator shares the Mac's network, so `127.0.0.1` works.
/// - Release builds must use a deployed HTTPS server. There isn't one yet,
///   so `releaseBaseURL` is a placeholder that will fail until it's replaced.
///
/// To point a Debug build somewhere else (for example a physical iPhone
/// talking to your Mac), add this launch argument in
/// Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments:
///
///     -CEDAPIBaseURL http://Your-Mac-Name.local:8000
///
/// Note: Neon's DATABASE_URL is NOT this URL. Only the backend talks to Neon.
enum APIConfig {
    static let localBaseURL = URL(string: "http://127.0.0.1:8000")!

    /// Replace with the deployed API (must be https://) before shipping.
    static let releaseBaseURL = URL(string: "https://replace-with-deployed-api.invalid")!

    static var baseURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "CEDAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return localBaseURL
        #else
        return releaseBaseURL
        #endif
    }
}
