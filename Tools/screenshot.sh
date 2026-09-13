#!/bin/bash
# Captures the running app's main window.
#
#   Tools/screenshot.sh out.png            capture as-is
#   Tools/screenshot.sh out.png "cmd 2"    send keystrokes first
#
# Window-scoped on purpose: never grabs the rest of the desktop. Requires
# Screen Recording (for the capture) and Accessibility (for the keystrokes)
# to be granted to the terminal app.
set -uo pipefail

OUT="${1:?usage: screenshot.sh <out.png> [keys...]}"
shift || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${TMPDIR:-/tmp}/openlist-dev-screenshot-cache"
mkdir -p "$CACHE"

# Prefer the reproducible development product. OPENLIST_APP can explicitly
# select another fixture; never discover or activate the installed production app.
APP="${OPENLIST_APP:-$ROOT/build/dev/DerivedData/Build/Products/Dev/Openlist Dev.app}"
if [ ! -d "$APP" ]; then
    echo "Build Openlist Dev first with Tools/build-dev.sh, or set OPENLIST_APP." >&2
    exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist") || exit 1

HELPER="$CACHE/winid"
# Rebuild whenever this script is newer than the cached binary, so edits to the
# embedded Swift below actually take effect.
if [ ! -x "$HELPER" ] || [ "$0" -nt "$HELPER" ]; then
cat > "$HELPER.swift" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
guard CommandLine.arguments.count > 1 else { exit(1) }
let appIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).map(\.processIdentifier))
let windows = list.filter { window in
    guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { return false }
    return appIDs.contains(pid)
}

func area(_ w: [String: Any]) -> Double {
    guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else { return 0 }
    return width * height
}

// OPENLIST_WINDOW=front takes the frontmost real window (the list is ordered
// front-to-back), which is how to reach Settings or Quick Add. The default
// takes the largest, which skips menus and popovers and lands on the main
// window. The area floor drops shadows and other tiny helper windows.
let real = windows.filter { area($0) > 10_000 }
let chosen = ProcessInfo.processInfo.environment["OPENLIST_WINDOW"] == "front"
    ? real.first
    : real.max { area($0) < area($1) }
print(chosen?[kCGWindowNumber as String] as? Int ?? -1)
SWIFT
xcrun swiftc -O -o "$HELPER" "$HELPER.swift" 2>/dev/null
fi

open "$APP" || exit 1

sleep 1

for keys in "$@"; do
    timeout 10 osascript -e "tell application \"System Events\" to tell (first application process whose bundle identifier is \"$BUNDLE_ID\") to $keys" >/dev/null 2>&1
    sleep 0.9
done
sleep 0.6

WID=$("$HELPER" "$BUNDLE_ID")
[ "$WID" = "-1" ] && { echo "no window found for $BUNDLE_ID"; exit 1; }
screencapture -x -o -l "$WID" "$OUT" && echo "captured window $WID → $OUT"
