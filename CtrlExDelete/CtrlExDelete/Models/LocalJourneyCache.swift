import Foundation
import OSLog

/// The on-phone copies of journey data, in one place: the files the app
/// writes, and how to forget them when they're known to be out of date.
nonisolated enum LocalJourneyFiles {
    /// JourneyCache: progress as the backend last sent it.
    static let journeyCache = "journey-cache.json"
    /// RoomMessageCache: Ced's room message for one local day.
    static let roomMessage = "room-message.json"
    /// The copies cleared after a reset (only copies: the backend has the data).
    static let fileNames = [journeyCache, roomMessage]
    /// Display state that belongs to the old journey: the bookshelf's "books already shown".
    static let settingKeys = ["roomBookshelfShown"]

    static func url(_ name: String) -> URL? {
        directory(create: true)?.appending(path: name)
    }

    static func directory(create: Bool) -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
    }

    struct PurgeResult: Equatable {
        var removedFiles: [String] = []
        var failedFiles: [String] = []
        var resetSettings: [String] = []
    }

    /// Removes exactly the journey copies (never a folder that happens to have
    /// a cache's name) and the bookshelf counter. Nothing else: not the
    /// installation ID, photos, the scrapbook PDF, the affirmations cache or
    /// other settings. Settings are only reset if every file went.
    static func purge(directory: URL?, defaults: UserDefaults, fileManager: FileManager = .default) -> PurgeResult {
        var result = PurgeResult()
        if let directory {
            for name in fileNames {
                let url = directory.appending(path: name)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                guard !isDirectory.boolValue else { result.failedFiles.append(name); continue }
                do {
                    try fileManager.removeItem(at: url)
                    result.removedFiles.append(name)
                } catch {
                    result.failedFiles.append(name)
                }
            }
        }
        guard result.failedFiles.isEmpty else { return result }
        result.resetSettings = settingKeys.filter { defaults.object(forKey: $0) != nil }
        result.resetSettings.forEach { defaults.removeObject(forKey: $0) }
        return result
    }
}

/// Notices, from the backend itself, that this installation was reset
/// (backend/scripts/reset_installation.py), so the phone forgets its copies of
/// the old journey and shows a fresh day 1, also after a Home Screen launch.
///
/// GET /check-ins/today reports which server record the installation ID has
/// (`installation`: exists + created_at). A reset deletes it; the next write
/// makes a new one with a new created_at. The app remembers the last one it
/// saw (per backend and installation ID) and decides only from a successful
/// response that carries the field: a failed request, an older backend
/// without the field, or a journey that is merely empty never clears anything.
nonisolated enum ServerResetCheck {
    struct Marker: Equatable {
        let exists: Bool
        let createdAt: String?
    }

    struct Decision: Equatable {
        let forgetLocalJourney: Bool
        let remember: String?     // the value to store (nil: leave the stored one)
    }

    static func defaultsKey(backendID: String) -> String { "CEDInstallationRecord.\(backendID)" }

    /// - stored: what was saved last time ("<installation-id>|<created_at or none>"), if anything.
    /// - cacheSavedAt: when the on-phone progress copy was saved, if there is one.
    /// - hasPersonalRoomMessage: the saved room message came from a check-in.
    /// - marker: from a successful response; nil when the backend doesn't send one (older version).
    static func decide(stored: String?, installationID: String, marker: Marker?,
                       cacheSavedAt: Date?, hasPersonalRoomMessage: Bool) -> Decision {
        guard let marker, !(marker.exists && marker.createdAt == nil) else {
            return Decision(forgetLocalJourney: false, remember: nil)
        }
        let current = marker.exists ? marker.createdAt! : "none"
        let token = "\(installationID.lowercased())|\(current)"

        let prefix = "\(installationID.lowercased())|"
        if let stored, stored.hasPrefix(prefix) {
            let previous = String(stored.dropFirst(prefix.count))
            if previous == current { return Decision(forgetLocalJourney: false, remember: nil) }
            // "none" before: nothing on the server then, so nothing old here to forget.
            return Decision(forgetLocalJourney: previous != "none", remember: token)
        }

        // Nothing saved yet (first launch of this version, or another ID):
        // the copies are out of date if the server has no record for them, or
        // its record is newer than the copy.
        let outdated: Bool
        if !marker.exists {
            outdated = cacheSavedAt != nil || hasPersonalRoomMessage
        } else if let cacheSavedAt, let created = parseDate(current) {
            outdated = cacheSavedAt < created
        } else {
            outdated = false
        }
        return Decision(forgetLocalJourney: outdated, remember: token)
    }

    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

#if DEBUG
/// DEBUG ONLY, a manual fallback (normally not needed: ServerResetCheck
/// forgets the old journey by itself after a reset). Clears the same copies
/// as ServerResetCheck when the app is started from Xcode with
///
///     -CEDClearLocalJourneyCache YES
///
/// once per value: later launches with the same value skip it, so leaving it
/// ticked doesn't clear again; untick it after use, or use a new value (e.g.
/// `2`) to clear again. Keeps the installation ID and everything else (see
/// LocalJourneyFiles.purge); makes no network request. Not in Release builds.
enum LocalJourneyCacheReset {
    static let argument = "CEDClearLocalJourneyCache"
    /// The request value already carried out (so one request runs once).
    static let doneKey = "CEDClearedLocalJourneyCacheRequest"

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
        let result = LocalJourneyFiles.purge(directory: directory, defaults: defaults, fileManager: fileManager)
        guard result.failedFiles.isEmpty else {
            return .failed(request: request, removedFiles: result.removedFiles, failedFiles: result.failedFiles)
        }
        defaults.set(request, forKey: doneKey)
        return .cleared(request: request, removedFiles: result.removedFiles, resetSettings: result.resetSettings)
    }

    /// Called once from MyApp.init, before any screen or JourneyStore reads a cache.
    static func runAtLaunch() {
        let outcome = perform(request: requestFromLaunchArguments(),
                              directory: LocalJourneyFiles.directory(create: false), defaults: .standard)
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
