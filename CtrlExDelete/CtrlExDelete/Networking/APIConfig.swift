import Foundation

/// The one place that decides which backend the app talks to.
///
/// - Debug builds use the FastAPI server on a developer's Mac. Its address is
///   built into the app (Config/Debug.xcconfig, plus each Mac's own
///   Config/DeveloperSettings.xcconfig), so it is the same whether the app is
///   started from Xcode or opened from the Home Screen. The Simulator uses
///   127.0.0.1; a physical iPhone uses the Mac address in DeveloperSettings.
/// - Release builds must use a deployed HTTPS server. There isn't one yet,
///   so `releaseBaseURL` is a placeholder that will fail until it's replaced.
///
/// For a one-off run against another server, a launch argument still wins
/// (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments), but only for runs
/// started by Xcode:
///
///     -CEDAPIBaseURL http://Your-Mac-Name.local:8000
///
/// Note: Neon's DATABASE_URL is NOT this URL. Only the backend talks to Neon.
enum APIConfig {
    static let localBaseURL = URL(string: "http://127.0.0.1:8000")!

    /// Replace with the deployed API (must be https://) before shipping.
    static let releaseBaseURL = URL(string: "https://replace-with-deployed-api.invalid")!

    static let baseURL: URL = {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "CEDAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return builtInDevServerURL ?? localBaseURL
        #else
        return releaseBaseURL
        #endif
    }()

    #if DEBUG
    /// http://<CED_DEV_SERVER_HOST>:<CED_DEV_SERVER_PORT> from the Debug Info.plist.
    private static var builtInDevServerURL: URL? {
        let info = Bundle.main.infoDictionary
        guard let host = (info?["CEDDevServerHost"] as? String)?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty, !host.contains("$(") else { return nil }
        let port = (info?["CEDDevServerPort"] as? String).flatMap(Int.init) ?? 8000
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }

    /// A physical iPhone can't reach the Mac at 127.0.0.1 (that's the phone itself).
    static var isMisconfiguredForDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ["127.0.0.1", "localhost"].contains(baseURL.host() ?? "")
        #endif
    }
    #endif
}
