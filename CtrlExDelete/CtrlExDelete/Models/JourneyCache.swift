import Foundation

/// The user's progress as the backend last sent it, kept on this device so
/// the app still has something to show when the backend can't be reached.
///
/// Only a copy: the backend stays the source of truth. It's written after
/// every successful load, read only when a load fails, never used to decide
/// whether the user has checked in, and belongs to one installation ID and
/// one backend (a copy from production never shows against a test backend).
/// Photo links in it are temporary and may have expired.
enum JourneyCache {
    struct Snapshot: Codable {
        var installationID: UUID
        var savedAt: Date
        var selection: SelectedActivityDTO?
        var reflections: [ReflectionDTO]
        var summary: ProgressSummaryDTO
        var books: [ShelfBookDTO]?      // nil in copies saved before the bookshelf
        var backend: String?            // APIConfig.backendID; nil in older copies (production)
    }

    private static var fileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "journey-cache.json")
    }

    static func save(selection: SelectedActivityDTO?, reflections: [ReflectionDTO], summary: ProgressSummaryDTO,
                     books: [ShelfBookDTO]) {
        guard let fileURL, let id = try? InstallationID.current() else { return }
        let snapshot = Snapshot(installationID: id, savedAt: .now, selection: selection,
                                reflections: reflections, summary: summary, books: books,
                                backend: APIConfig.backendID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// nil if there's no copy, or it belongs to a different installation or backend.
    static func load() -> Snapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              let id = try? InstallationID.current(), snapshot.installationID == id,
              APIConfig.isCurrentBackend(snapshot.backend) else { return nil }
        return snapshot
    }
}
