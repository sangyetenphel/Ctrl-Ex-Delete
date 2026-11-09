#!/bin/sh
# Runs the Mac-side tests for app code that only needs Foundation.
# Not part of the app target (this folder isn't synced into Xcode).
#   cd CtrlExDelete && ./DevTests/run.sh
set -e
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/ced-devtests-$$"
mkdir -p "$out"
trap 'rm -rf "$out"' EXIT

# The reset must stay local: no Keychain, network or server code in it.
if grep -n -E 'SecItem|kSec|URLSession|APIClient|InstallationID|http' CtrlExDelete/Models/LocalJourneyCache.swift; then
    echo "FAIL  LocalJourneyCache.swift must not touch the Keychain, the network or the backend"; exit 1
fi
echo "  ok    LocalJourneyCache.swift has no Keychain, network or backend code"

# The two cache owners use the shared names (so the reset clears the real files).
grep -q 'LocalJourneyFiles.journeyCache' CtrlExDelete/Models/JourneyCache.swift
grep -q 'LocalJourneyFiles.roomMessage' CtrlExDelete/Models/RoomMessage.swift
echo "  ok    JourneyCache and RoomMessageCache use LocalJourneyFiles"

# Top-level test code must be in a file named main.swift.
cp DevTests/LocalJourneyCacheResetTests.swift "$out/main.swift"
xcrun swiftc -D DEBUG -o "$out/tests" CtrlExDelete/Models/LocalJourneyCache.swift "$out/main.swift"
"$out/tests"

# When Ced's room card invites the user to try an activity.
cp DevTests/RoomDialogueTests.swift "$out/main.swift"
xcrun swiftc -o "$out/room-dialogue-tests" CtrlExDelete/Models/RoomDialogue.swift "$out/main.swift"
"$out/room-dialogue-tests"
