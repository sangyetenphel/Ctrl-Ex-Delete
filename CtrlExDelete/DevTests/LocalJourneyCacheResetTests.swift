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

print(failures == 0 ? "All passed." : "\(failures) FAILED.")
exit(failures == 0 ? 0 : 1)
