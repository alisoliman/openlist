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
fail_bundle() {
    printf 'Invalid release bundle: %s\n' "$1" >&2
    exit 1
}
# Bash 3.2 can ignore errexit for [[ $(command) == expected ]].
# Check command failures and mismatches explicitly before reporting success.
require_metadata() {
    local plist="$1" key="$2" expected="$3" actual
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist") || \
        fail_bundle "$plist: cannot read $key"
    [[ "$actual" == "$expected" ]] || \
        fail_bundle "$plist: $key must be '$expected' (found '$actual')"
}
[[ -f "$HELPER" && -x "$HELPER" && ! -L "$HELPER" ]] || \
    fail_helper "expected an embedded executable at Contents/MacOS/openlist-mcp"
HELPER_TYPE=$(file -b "$HELPER") || fail_helper "cannot read the helper's executable format"
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
    [[ -f "$plist" && -r "$plist" && ! -L "$plist" ]] || \
        fail_bundle "$plist: expected readable, embedded Info.plist"
    executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist") || \
        fail_bundle "$plist: cannot read CFBundleExecutable"
    [[ -n "$executable" && "$executable" != */* && "$executable" != . && "$executable" != .. ]] || \
        fail_bundle "$plist: CFBundleExecutable must name a file inside Contents/MacOS"
    architectures=$(lipo -archs "$bundle/Contents/MacOS/$executable" 2>/dev/null) || \
        fail_bundle "$bundle: cannot read executable architecture"
    [[ "$architectures" == arm64 ]] || \
        fail_bundle "$bundle: architecture must be 'arm64' (found '$architectures')"
    require_metadata "$plist" CFBundleShortVersionString "$VERSION"
    require_metadata "$plist" CFBundleVersion "$BUILD_NUMBER"
    require_metadata "$plist" LSMinimumSystemVersion 26.5
    identifier=solimanali.openlist
    if [[ "$bundle" != "$APP" ]]; then
        identifier=solimanali.openlist.OpenlistWidget
    fi
    require_metadata "$plist" CFBundleIdentifier "$identifier"
    if [[ "$bundle" == "$APP" ]]; then
        python3 - "$plist" <<'PY' || fail_bundle "$plist: CFBundleURLTypes: invalid production item-link registration"
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
expected = [{'CFBundleTypeRole': 'Viewer', 'CFBundleURLName': 'solimanali.openlist.item', 'CFBundleURLSchemes': ['openlist']}]
if info.get('CFBundleURLTypes') != expected:
    raise SystemExit('Production must register only the openlist item-link scheme')
PY
    fi
    if /usr/libexec/PlistBuddy -c 'Print :OpenlistReviewSession' "$plist" >/dev/null 2>&1; then
        fail_bundle "$plist: OpenlistReviewSession must not be present in a release"
    fi
    if /usr/libexec/PlistBuddy -c 'Print :OpenlistDevelopment' "$plist" >/dev/null 2>&1; then
        fail_bundle "$plist: OpenlistDevelopment must not be present in a release"
    fi
    if [[ "$bundle" == "$APP" ]]; then
        python3 "$(dirname "$0")/verify-drag-types.py" "$plist" release
    fi
    echo "Verified arm64, version $VERSION ($BUILD_NUMBER), macOS 26.5: $bundle"
done
