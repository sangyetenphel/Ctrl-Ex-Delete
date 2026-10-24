import Foundation

/// Ced's message in the healing room for one local day: chosen by the backend
/// from today's check-in (or a "let's check in" message before it), and kept
/// on the phone so it's still there during loading or without a connection.
struct RoomMessageRecord: Codable, Equatable {
    let text: String
    let pattern: String
    let checkInId: Int?          // nil before today's check-in
    let localDate: String        // the local day it belongs to
    let installationID: UUID?

    var isPersonal: Bool { checkInId != nil }

    /// Shown when no message for today is known (never yesterday's).
    static let neutralText = "One small step at a time. I\u{2019}m here with you."
}

/// The last room message, on the phone (one small file).
enum RoomMessageCache {
    private static var url: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "room-message.json")
    }

    /// The saved message, if it belongs to this installation.
    static func load() -> RoomMessageRecord? {
        guard let url, let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(RoomMessageRecord.self, from: data) else { return nil }
        if let saved = record.installationID, let current = try? InstallationID.current(), saved != current {
            return nil
        }
        return record
    }

    static func save(_ record: RoomMessageRecord) {
        guard let url, let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
