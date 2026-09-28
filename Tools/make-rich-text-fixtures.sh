#!/bin/bash
# Regenerates Tools/RichTextParityChecks/Fixtures: the Mac writes its
# archives (mac-*.rtf), then the iPhone's codec, run on an iOS simulator,
# checks it reads them as the Mac does and writes its own archives and edits
# of the Mac's (ios-*.rtf), which Tools/run-rich-text-parity-checks.sh then
# decodes on the Mac. Run it after changing RichTextCodec, either platform's
# NXEditor or the samples, and commit the fixtures. Needs the iOS 27
# simulator runtime; it creates a simulator and deletes it again.
set -euo pipefail
cd "$(dirname "$0")/.."
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0
DEVICE_TYPE=${OPENLIST_IOS_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro}
xcrun simctl list runtimes | grep -q "$RUNTIME" || {
    echo "The iOS 27 simulator runtime is missing. Install it with: xcodebuild -downloadPlatform iOS" >&2; exit 1; }
OUT=$(mktemp -d)
UDID=
cleanup() {
    if [[ -n "$UDID" ]]; then
        xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
    fi
    rm -rf "$OUT"
}
trap cleanup EXIT
FIXTURES="$PWD/Tools/RichTextParityChecks/Fixtures"
mkdir -p "$FIXTURES"

xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/mac" \
  openlist/Model/BlockKind.swift openlist/Next/NextEditorTypography.swift openlist/Services/RichTextCodec.swift \
  Tools/RichTextParityChecks/Samples.swift Tools/RichTextParityChecks/main.swift
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator -swift-version 6 -default-isolation MainActor \
  -o "$OUT/ios" openlist/Model/BlockKind.swift OpenlistiOS/Platform/EditorTypography.swift openlist/Services/RichTextCodec.swift \
  Tools/RichTextParityChecks/Samples.swift Tools/RichTextParityChecks/iOS/main.swift

"$OUT/mac" write-mac-fixtures "$FIXTURES"
UDID=$(xcrun simctl create "Openlist rich text fixtures $$" "$DEVICE_TYPE" "$RUNTIME")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl spawn "$UDID" "$OUT/ios" "$FIXTURES"
"$OUT/mac"
