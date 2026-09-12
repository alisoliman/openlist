#!/bin/bash
set -euo pipefail
APP=${1:?Usage: verify-release.sh APP VERSION BUILD_NUMBER}
VERSION=${2:?Missing version}
BUILD_NUMBER=${3:?Missing build number}
HELPER="$APP/Contents/MacOS/openlist-mcp"
fail_helper() {
    echo "Invalid release MCP helper: $1" >&2
    exit 1
}
[[ -f "$HELPER" && -x "$HELPER" && ! -L "$HELPER" ]] || \
    fail_helper "expected an embedded executable at Contents/MacOS/openlist-mcp"
HELPER_TYPE=$(file -b "$HELPER")
[[ "$HELPER_TYPE" == *Mach-O*executable* ]] || \
    fail_helper "Contents/MacOS/openlist-mcp must be a native Mach-O executable"
HELPER_ARCHS=$(lipo -archs "$HELPER" 2>/dev/null) || \
    fail_helper "cannot read the helper's Mach-O architecture"
[[ "$HELPER_ARCHS" == arm64 ]] || fail_helper "expected arm64 architecture"
HELPER_USAGE=$(env -u OPENLIST_MCP_TOKEN -u OPENLIST_MCP_URL "$HELPER" --help </dev/null) || \
    fail_helper "--help must succeed offline without an MCP token or running app"
[[ "$HELPER_USAGE" == *"Usage: openlist-mcp"* && "$HELPER_USAGE" == *"OPENLIST_MCP_TOKEN"* ]] || \
    fail_helper "--help did not return the expected launcher usage"
echo "Verified native arm64 MCP helper and offline --help: $HELPER"
NOTICES="$APP/Contents/Resources/ThirdPartyNotices.txt"
if [[ ! -f "$NOTICES" || ! -s "$NOTICES" || -L "$NOTICES" ]]; then
    echo "Release requires nonempty bundled dependency notices at Contents/Resources/ThirdPartyNotices.txt" >&2
    exit 1
fi
echo "Verified bundled dependency notices: $NOTICES"
for bundle in "$APP" "$APP/Contents/PlugIns/OpenlistWidget.appex"; do
    plist="$bundle/Contents/Info.plist"
    executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
    [[ $(lipo -archs "$bundle/Contents/MacOS/$executable") == arm64 ]]
    [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") == "$VERSION" ]]
    [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist") == "$BUILD_NUMBER" ]]
    [[ $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist") == 26.5 ]]
    if /usr/libexec/PlistBuddy -c 'Print :OpenlistReviewSession' "$plist" >/dev/null 2>&1; then
        echo "Review fixture configuration leaked into release" >&2; exit 1
    fi
    echo "Verified arm64, version $VERSION ($BUILD_NUMBER), macOS 26.5: $bundle"
done
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist") == solimanali.openlist ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/PlugIns/OpenlistWidget.appex/Contents/Info.plist") == solimanali.openlist.OpenlistWidget ]]
