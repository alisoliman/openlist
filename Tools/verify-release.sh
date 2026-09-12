#!/bin/bash
set -euo pipefail
APP=${1:?Usage: verify-release.sh APP VERSION BUILD_NUMBER}
VERSION=${2:?Missing version}
BUILD_NUMBER=${3:?Missing build number}
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
