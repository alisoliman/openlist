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
CACHE="${TMPDIR:-/tmp}/openlist-screenshot-cache"
mkdir -p "$CACHE"

# `xcodebuild -showBuildSettings` takes ~15s, so the product path and the
# window-id helper are both cached between calls.
if [ ! -s "$CACHE/app-path" ]; then
    xcodebuild -project "$ROOT/openlist.xcodeproj" -scheme openlist -configuration Debug \
        -showBuildSettings 2>/dev/null \
        | awk -F'= ' '/BUILT_PRODUCTS_DIR/ {print $2 "/openlist.app"; exit}' > "$CACHE/app-path"
fi
APP=$(cat "$CACHE/app-path")

HELPER="$CACHE/winid"
# Rebuild whenever this script is newer than the cached binary, so edits to the
# embedded Swift below actually take effect.
if [ ! -x "$HELPER" ] || [ "$0" -nt "$HELPER" ]; then
cat > "$HELPER.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0[kCGWindowOwnerName as String] as? String)?.lowercased().contains("openlist") == true }

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

pgrep -f "MacOS/openlist" >/dev/null || { "$APP/Contents/MacOS/openlist" >/tmp/openlist_run.log 2>&1 & sleep 7; }
timeout 5 osascript -e 'tell application "openlist" to activate' >/dev/null 2>&1
sleep 1

for keys in "$@"; do
    timeout 10 osascript -e "tell application \"System Events\" to tell process \"openlist\" to $keys" >/dev/null 2>&1
    sleep 0.9
done
sleep 0.6

WID=$("$HELPER")
[ "$WID" = "-1" ] && { echo "no openlist window found"; exit 1; }
screencapture -x -o -l "$WID" "$OUT" && echo "captured window $WID → $OUT"
