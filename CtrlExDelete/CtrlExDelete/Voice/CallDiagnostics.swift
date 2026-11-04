import os

/// TEMPORARY call diagnostics: connection states, routes, formats, chunk and
/// byte counts. Never audio, transcripts or keys.
///
/// Read them while a call runs:
///   xcrun simctl spawn booted log stream --level info \
///     --predicate 'subsystem == "com.ctrlexdelete" AND category == "call"'
/// (or Console.app on the Mac with the iPhone connected, filtered to "call").
nonisolated enum CallDiagnostics {
    #if DEBUG
    static let enabled = true
    #else
    static let enabled = false
    #endif
    private static let logger = Logger(subsystem: "com.ctrlexdelete", category: "call")

    static func log(_ message: String) {
        guard enabled else { return }
        logger.info("\(message, privacy: .public)")
    }
}
