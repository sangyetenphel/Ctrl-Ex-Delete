import Foundation
import os

/// The one place that decides which backend the app talks to.
///
/// - Every build, Debug and Release, uses the deployed backend on Render
///   (`deployedBaseURL`, HTTPS; voice calls use WSS on the same host). It is
///   built into the app, so it is the same whether the app is started from
///   Xcode or opened from the Home Screen.
/// - Another deployed backend (e.g. a Render test service) is opt-in, Debug
///   only: `CED_API_BASE_URL = ced-backend-test.onrender.com` in your Mac's
///   Config/DeveloperSettings.xcconfig. It's built into the Debug app, so it
///   also applies when the app is opened from the Home Screen.
/// - Local development is opt-in, Debug only: `CED_BACKEND = local` in your
///   Mac's Config/DeveloperSettings.xcconfig uses the FastAPI server on your
///   Mac instead (127.0.0.1 in the Simulator; on an iPhone, the Mac address
///   in CED_DEV_SERVER_HOST). See DeveloperSettings.example.xcconfig.
///
/// For a one-off run against another server, a launch argument still wins
/// (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments), but only for runs
/// started by Xcode:
///
///     -CEDAPIBaseURL http://Your-Mac-Name.local:8000
///
/// Note: Neon's DATABASE_URL is NOT this URL. Only the backend talks to Neon,
/// and no backend credential is ever in the app.
enum APIConfig {
    /// The Render web service (backend/README.md, "Deploying to Render").
    static let deployedBaseURL = URL(string: "https://ctrl-ex-delete-api.onrender.com")!

    static let localBaseURL = URL(string: "http://127.0.0.1:8000")!

    /// Where the base URL came from (Debug diagnostics; Release is always `.builtIn`).
    enum Source: String {
        case launchArgument = "launch argument -CEDAPIBaseURL"
        case developerSettings = "CED_API_BASE_URL (DeveloperSettings.xcconfig)"
        case invalidDeveloperSettings = "CED_API_BASE_URL is not a valid URL"
        case localServer = "CED_BACKEND = local"
        case builtIn = "built-in production"
    }

    static let resolved: (url: URL, source: Source) = {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "CEDAPIBaseURL"),
           let url = URL(string: override) {
            return (url, .launchArgument)
        }
        switch configuredBaseURL {
        case .some(.some(let url)):
            return (url, .developerSettings)
        case .some(.none):
            // Set but unusable: never fall back to production with test data.
            return (invalidConfigURL, .invalidDeveloperSettings)
        case .none:
            break
        }
        if usesLocalServer {
            return (builtInDevServerURL ?? localBaseURL, .localServer)
        }
        #endif
        return (deployedBaseURL, .builtIn)
    }()

    static var baseURL: URL { resolved.url }

    /// Whether this is a deployed backend, which sleeps when idle (Render Free).
    static var isDeployed: Bool {
        baseURL == deployedBaseURL || baseURL.host()?.hasSuffix(".onrender.com") == true
    }

    /// Names the backend for on-phone copies of its data (JourneyCache,
    /// RoomMessageCache), so a copy from one backend never shows up while the
    /// app uses another. Copies saved before this existed count as production.
    static var backendID: String { backendID(for: baseURL) }

    static func backendID(for url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        return url.port.map { "\(host):\($0)" } ?? host
    }

    static func isCurrentBackend(_ savedID: String?) -> Bool {
        (savedID ?? backendID(for: deployedBaseURL)) == backendID
    }

    #if DEBUG
    /// A host that can never resolve (.invalid is reserved), used when
    /// CED_API_BASE_URL is set but unusable, so requests fail visibly.
    static let invalidConfigURL = URL(string: "https://ced-api-base-url-not-valid.invalid")!

    /// CED_API_BASE_URL from the Debug Info.plist: nil if unset, .some(nil)
    /// if set but not a usable URL. A bare host means https://host. Because
    /// "//" starts a comment in xcconfig files, a full URL must be written
    /// as https:/$()/host; a cut-off value ("https:") counts as invalid.
    private static var configuredBaseURL: URL?? {
        guard let raw = (Bundle.main.infoDictionary?["CEDAPIBaseURLSetting"] as? String)?
                .trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, !raw.contains("$(") else { return nil }
        let text = raw.contains("://") ? raw : "https://\(raw)"
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty, host.contains(".") || host == "localhost",
              let url = components.url else { return .some(nil) }
        return .some(url)
    }

    /// `CED_BACKEND = local` in DeveloperSettings.xcconfig (Debug Info.plist).
    private static var usesLocalServer: Bool {
        let value = Bundle.main.infoDictionary?["CEDBackend"] as? String
        return value?.trimmingCharacters(in: .whitespaces).lowercased() == "local"
    }

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

    /// Debug-only launch line: which backend and why. Host only: no user
    /// data, no installation ID. Shown in Xcode's console, and in Console.app
    /// (Mac, phone selected, subsystem CtrlExDelete) for Home Screen launches.
    static func logActiveBackend() {
        let logger = Logger(subsystem: "CtrlExDelete", category: "backend")
        let host = backendID
        let source = resolved.source.rawValue
        if resolved.source == .invalidDeveloperSettings {
            logger.error("Backend: none. \(source, privacy: .public); write the host only, e.g. ced-backend-test.onrender.com")
        } else {
            logger.notice("Backend: \(host, privacy: .public) (\(source, privacy: .public))")
        }
    }
    #endif
}
