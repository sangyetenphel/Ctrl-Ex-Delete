import Foundation
import OSLog

/// The names of the on-phone copies of journey data (one place, so the
/// Debug reset below always clears exactly the files the app writes).
nonisolated enum LocalJourneyFiles {
    /// JourneyCache: progress as the backend last sent it.
    static let journeyCache = "journey-cache.json"
    /// RoomMessageCache: Ced's room message for one local day.
    static let roomMessage = "room-message.json"

    static func url(_ name: String) -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: name)
    }
}

#if DEBUG
/// DEBUG ONLY: clears the phone's copies of journey data after an
/// installation was reset on the backend (backend/scripts/reset_installation.py),
/// so nothing from before the reset shows up, even offline.
///
/// Requested with a launch argument (Xcode ▸ Product ▸ Scheme ▸ Edit Scheme ▸
/// Run ▸ Arguments), which only exists for runs started by Xcode:
///
///     -CEDClearLocalJourneyCache YES
///
/// It runs ONCE per request value: later launches with the same value skip
/// it (the value done is remembered), so leaving it ticked doesn't clear
/// again. Untick it after use; to clear again later, run once with a new
/// value (e.g. `-CEDClearLocalJourneyCache 2`).
///
/// Clears: journey-cache.json, room-message.json (Application Support) and
/// the bookshelf's "books already shown" counter (display state only).
/// Never touches: the Keychain installation ID (the phone reconnects as the
/// same, now fresh, installation), photos, the saved scrapbook PDF, the
/// affirmations catalog cache, other settings, or anything on a server:
/// it only removes files on this phone and makes no network request.
/// Release builds don't contain this code.
enum LocalJourneyCacheReset {
    static let argument = "CEDClearLocalJourneyCache"
    /// The request value already carried out (so one request runs once).
    static let doneKey = "CEDClearedLocalJourneyCacheRequest"
    static let fileNames = [LocalJourneyFiles.journeyCache, LocalJourneyFiles.roomMessage]
    static let settingKeys = ["roomBookshelfShown"]

    enum Outcome: Equatable {
        case notRequested
        case alreadyDone(request: String)
        case cleared(request: String, removedFiles: [String], resetSettings: [String])
        /// Some file couldn't be removed; not marked done, so the next launch tries again.
        case failed(request: String, removedFiles: [String], failedFiles: [String])
    }

    /// The value of the launch argument, read from the launch arguments only
    /// (never from saved settings), or nil.
    static func requestFromLaunchArguments() -> String? {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[argument] as? String
    }

    /// Does the work; everything it touches is passed in (testable).
    static func perform(request rawRequest: String?, directory: URL?, defaults: UserDefaults,
                        fileManager: FileManager = .default) -> Outcome {
        guard let request = rawRequest?.trimmingCharacters(in: .whitespaces), !request.isEmpty,
              !["NO", "0", "FALSE"].contains(request.uppercased()) else { return .notRequested }
        if defaults.string(forKey: doneKey) == request { return .alreadyDone(request: request) }

        var removed: [String] = [], failed: [String] = []
        if let directory {
            for name in fileNames {
                let url = directory.appending(path: name)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                // Only the app's own cache files: never a folder that happens to have the name.
                guard !isDirectory.boolValue else { failed.append(name); continue }
                do {
                    try fileManager.removeItem(at: url)
                    removed.append(name)
                } catch {
                    failed.append(name)
                }
            }
        }
        guard failed.isEmpty else { return .failed(request: request, removedFiles: removed, failedFiles: failed) }

        let reset = settingKeys.filter { defaults.object(forKey: $0) != nil }
        reset.forEach { defaults.removeObject(forKey: $0) }
        defaults.set(request, forKey: doneKey)
        return .cleared(request: request, removedFiles: removed, resetSettings: reset)
    }

    /// Called once from MyApp.init, before any screen or JourneyStore reads a cache.
    static func runAtLaunch() {
        let directory = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let outcome = perform(request: requestFromLaunchArguments(), directory: directory, defaults: .standard)
        let logger = Logger(subsystem: "CtrlExDelete", category: "debug-reset")
        switch outcome {
        case .notRequested:
            break
        case .alreadyDone(let request):
            logger.notice("Local journey cache: already cleared for request \(request, privacy: .public); untick -\(argument, privacy: .public) or use a new value to clear again.")
        case .cleared(let request, let files, let settings):
            logger.notice("Local journey cache cleared (request \(request, privacy: .public)): files \(files.joined(separator: ", "), privacy: .public); settings \(settings.joined(separator: ", "), privacy: .public). Installation ID kept. Untick -\(argument, privacy: .public) now.")
        case .failed(let request, let files, let failedFiles):
            logger.error("Local journey cache NOT fully cleared (request \(request, privacy: .public)): removed \(files.joined(separator: ", "), privacy: .public); failed \(failedFiles.joined(separator: ", "), privacy: .public). It will try again next launch.")
        }
    }
}
#endif
