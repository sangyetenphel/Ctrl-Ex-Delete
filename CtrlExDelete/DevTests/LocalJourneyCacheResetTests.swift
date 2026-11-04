// Tests for the Debug-only LocalJourneyCacheReset (Models/LocalJourneyCache.swift).
// Not part of the app target: run on the Mac with ./DevTests/run.sh
// (compiles the real source file with -D DEBUG, in a temporary folder).
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition { print("  ok    \(message)") } else { failures += 1; print("  FAIL  \(message) (line \(line))") }
}

let fm = FileManager.default

/// A fresh fake Application Support folder and a private settings store.
func setUp() -> (URL, UserDefaults) {
    let dir = fm.temporaryDirectory.appending(path: "ced-cache-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in ["journey-cache.json", "room-message.json", "affirmations-cache.json", "unrelated.json"] {
        try! Data("{}".utf8).write(to: dir.appending(path: name))
    }
    let pdfDir = dir.appending(path: "FarewellScrapbook", directoryHint: .isDirectory)
    try! fm.createDirectory(at: pdfDir, withIntermediateDirectories: true)
    try! Data("%PDF".utf8).write(to: pdfDir.appending(path: "My Ctrl+Ex+Delete Scrapbook.pdf"))
    let suite = "ced-cache-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set(5, forKey: "roomBookshelfShown")
    defaults.set("keep me", forKey: "someOtherSetting")
    return (dir, defaults)
}

func exists(_ dir: URL, _ name: String) -> Bool { fm.fileExists(atPath: dir.appending(path: name).path) }

func keptUnrelated(_ dir: URL, _ defaults: UserDefaults) -> Bool {
    exists(dir, "affirmations-cache.json") && exists(dir, "unrelated.json")
        && exists(dir, "FarewellScrapbook/My Ctrl+Ex+Delete Scrapbook.pdf")
        && defaults.string(forKey: "someOtherSetting") == "keep me"
}

print("LocalJourneyCacheReset")

do {  // Not requested: nothing happens.
    let (dir, defaults) = setUp()
    for value: String? in [nil, "", "  ", "NO", "no", "0", "false"] {
        check(LocalJourneyCacheReset.perform(request: value, directory: dir, defaults: defaults) == .notRequested,
              "no request for \(value.map { "'\($0)'" } ?? "nil")")
    }
    check(exists(dir, "journey-cache.json") && exists(dir, "room-message.json"), "caches kept when not requested")
    check(defaults.integer(forKey: "roomBookshelfShown") == 5, "bookshelf counter kept when not requested")
}

do {  // Requested: exactly the journey caches go; everything else stays.
    let (dir, defaults) = setUp()
    let outcome = LocalJourneyCacheReset.perform(request: "YES", directory: dir, defaults: defaults)
    check(outcome == .cleared(request: "YES", removedFiles: ["journey-cache.json", "room-message.json"],
                              resetSettings: ["roomBookshelfShown"]), "YES clears the two caches and the counter")
    check(!exists(dir, "journey-cache.json") && !exists(dir, "room-message.json"), "cache files removed")
    check(defaults.object(forKey: "roomBookshelfShown") == nil, "bookshelf counter reset")
    check(keptUnrelated(dir, defaults), "affirmations cache, other files, scrapbook PDF and other settings kept")

    // Once per request: the same value again does nothing, even if the files came back.
    try! Data("{}".utf8).write(to: dir.appending(path: "journey-cache.json"))
    defaults.set(2, forKey: "roomBookshelfShown")
    check(LocalJourneyCacheReset.perform(request: "YES", directory: dir, defaults: defaults) == .alreadyDone(request: "YES"),
          "same value again: already done")
    check(exists(dir, "journey-cache.json") && defaults.integer(forKey: "roomBookshelfShown") == 2,
          "nothing cleared the second time")

    // A new value is a new request.
    check(LocalJourneyCacheReset.perform(request: "2", directory: dir, defaults: defaults)
          == .cleared(request: "2", removedFiles: ["journey-cache.json"], resetSettings: ["roomBookshelfShown"]),
          "a new value clears again (only what exists)")
    check(keptUnrelated(dir, defaults), "unrelated data still kept")
}

do {  // Nothing to clear is still a completed request.
    let (dir, defaults) = setUp()
    try! fm.removeItem(at: dir.appending(path: "journey-cache.json"))
    try! fm.removeItem(at: dir.appending(path: "room-message.json"))
    defaults.removeObject(forKey: "roomBookshelfShown")
    check(LocalJourneyCacheReset.perform(request: "YES", directory: dir, defaults: defaults)
          == .cleared(request: "YES", removedFiles: [], resetSettings: []), "empty phone: cleared, nothing to remove")
}

do {  // A folder with a cache's name is never deleted; the request isn't marked done.
    let (dir, defaults) = setUp()
    try! fm.removeItem(at: dir.appending(path: "room-message.json"))
    let folder = dir.appending(path: "room-message.json", directoryHint: .isDirectory)
    try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try! Data("x".utf8).write(to: folder.appending(path: "inside.txt"))
    let outcome = LocalJourneyCacheReset.perform(request: "YES", directory: dir, defaults: defaults)
    check(outcome == .failed(request: "YES", removedFiles: ["journey-cache.json"], failedFiles: ["room-message.json"]),
          "unexpected folder reported as a failure")
    check(exists(dir, "room-message.json/inside.txt"), "the folder and its contents are untouched")
    check(defaults.string(forKey: LocalJourneyCacheReset.doneKey) == nil
          && defaults.integer(forKey: "roomBookshelfShown") == 5, "not marked done; counter kept, so it can retry")
}

do {  // The launch argument is read from the launch arguments only, never saved settings.
    UserDefaults.standard.set("YES", forKey: LocalJourneyCacheReset.argument)
    check(LocalJourneyCacheReset.requestFromLaunchArguments() == nil, "a saved setting with the name doesn't count")
    UserDefaults.standard.removeObject(forKey: LocalJourneyCacheReset.argument)
}

print("ServerResetCheck (automatic, after a server-side reset)")

let A = "AAAAAAAA-0000-4000-8000-000000000001", B = "BBBBBBBB-0000-4000-8000-000000000002"
let t1 = "2026-11-04T10:41:16.178787Z", t2 = "2026-11-04T12:00:00.5Z"
let before = ServerResetCheck.parseDate(t1)!.addingTimeInterval(-3600)
let after = ServerResetCheck.parseDate(t1)!.addingTimeInterval(60)
func decide(_ stored: String?, _ marker: ServerResetCheck.Marker?, id: String = A, saved: Date? = nil,
            personal: Bool = false) -> ServerResetCheck.Decision {
    ServerResetCheck.decide(stored: stored, installationID: id, marker: marker, cacheSavedAt: saved,
                            hasPersonalRoomMessage: personal)
}
let none = ServerResetCheck.Marker(exists: false, createdAt: nil)
let rec1 = ServerResetCheck.Marker(exists: true, createdAt: t1), rec2 = ServerResetCheck.Marker(exists: true, createdAt: t2)
let a = A.lowercased()
check(ServerResetCheck.parseDate("2026-11-04T12:39:21.400478-05:00") == ServerResetCheck.parseDate("2026-11-04T17:39:21.400Z"),
      "parses the server's format (microseconds, offset)")
check(ServerResetCheck.parseDate("2026-11-04T17:39:21+00:00") != nil, "parses without fractional seconds")

check(decide("\(a)|\(t1)", nil, saved: before, personal: true) == .init(forgetLocalJourney: false, remember: nil),
      "older backend (no marker): nothing forgotten, nothing stored")
check(decide("\(a)|\(t1)", .init(exists: true, createdAt: nil)) == .init(forgetLocalJourney: false, remember: nil),
      "incomplete marker: no decision")
check(decide("\(a)|\(t1)", rec1, saved: before) == .init(forgetLocalJourney: false, remember: nil),
      "same record as last time: kept")
check(decide("\(a)|\(t1)", none, saved: after) == .init(forgetLocalJourney: true, remember: "\(a)|none"),
      "record gone (reset): forget")
check(decide("\(a)|\(t1)", rec2, saved: after) == .init(forgetLocalJourney: true, remember: "\(a)|\(t2)"),
      "new record (reset, then a new write): forget")
check(decide("\(a)|none", rec1, saved: after) == .init(forgetLocalJourney: false, remember: "\(a)|\(t1)"),
      "first write after a fresh start: nothing to forget")
check(decide("\(a)|none", none) == .init(forgetLocalJourney: false, remember: nil),
      "still nothing on the server: no change (an empty journey is not a reset)")
check(decide(nil, none) == .init(forgetLocalJourney: false, remember: "\(a)|none"),
      "new phone, nothing anywhere: remembered, nothing forgotten")
check(decide(nil, none, saved: after) == .init(forgetLocalJourney: true, remember: "\(a)|none"),
      "updated after a reset (no record, but a progress copy): forget")
check(decide(nil, none, personal: true).forgetLocalJourney, "updated after a reset (old personal room message): forget")
check(decide(nil, rec1, saved: before).forgetLocalJourney, "copy older than the server record: forget")
check(!decide(nil, rec1, saved: after).forgetLocalJourney, "copy newer than the server record: kept")
check(decide("\(B.lowercased())|\(t1)", rec1, id: A, saved: after) == .init(forgetLocalJourney: false, remember: "\(a)|\(t1)"),
      "a value saved for another installation ID is ignored")

do {  // Two phones: A is reset, B isn't. Only A forgets.
    let (dirA, defaultsA) = setUp(), (dirB, defaultsB) = setUp()
    let key = ServerResetCheck.defaultsKey(backendID: "ctrl-ex-delete-api.onrender.com")
    defaultsA.set("\(a)|\(t1)", forKey: key)
    defaultsB.set("\(B.lowercased())|\(t2)", forKey: key)
    let dA = ServerResetCheck.decide(stored: defaultsA.string(forKey: key), installationID: A, marker: none,
                                     cacheSavedAt: after, hasPersonalRoomMessage: true)
    let dB = ServerResetCheck.decide(stored: defaultsB.string(forKey: key), installationID: B, marker: rec2,
                                     cacheSavedAt: after, hasPersonalRoomMessage: true)
    if dA.forgetLocalJourney { _ = LocalJourneyFiles.purge(directory: dirA, defaults: defaultsA) }
    if dB.forgetLocalJourney { _ = LocalJourneyFiles.purge(directory: dirB, defaults: defaultsB) }
    check(!exists(dirA, "journey-cache.json") && !exists(dirA, "room-message.json")
          && defaultsA.object(forKey: "roomBookshelfShown") == nil, "phone A: old journey copies forgotten")
    check(keptUnrelated(dirA, defaultsA), "phone A: photos/PDF/affirmations/other settings kept")
    check(exists(dirB, "journey-cache.json") && exists(dirB, "room-message.json")
          && defaultsB.integer(forKey: "roomBookshelfShown") == 5, "phone B: unaffected")
}

do {  // A failed request never reaches decide(): nothing happens without a marker.
    let (dir, defaults) = setUp()
    let d = ServerResetCheck.decide(stored: nil, installationID: A, marker: nil, cacheSavedAt: after,
                                    hasPersonalRoomMessage: true)
    if d.forgetLocalJourney { _ = LocalJourneyFiles.purge(directory: dir, defaults: defaults) }
    check(exists(dir, "journey-cache.json") && defaults.integer(forKey: "roomBookshelfShown") == 5,
          "no marker (failure or older backend): local progress kept")
}

print(failures == 0 ? "All passed." : "\(failures) FAILED.")
exit(failures == 0 ? 0 : 1)
