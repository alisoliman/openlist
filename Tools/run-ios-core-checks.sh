#!/bin/bash
# Type-checks every Swift file the iOS app and widget compile, exactly as the
# project assigns them (Tools/ios-sources.py), against the iOS simulator SDK
# with the targets' own concurrency settings, in each configuration's
# compilation conditions. Catches a macOS-side edit that breaks iOS (an AppKit
# call in a shared Store file, a new file the shared set now needs) without a
# simulator, signing or an Apple account. Membership is checked first: the
# project must match Tools/iOS/shared-sources.txt, the Mac UI stays out, and
# every Model file is in (both apps must build the same CloudKit schema).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 -B Tools/add-ios-targets.py --check
SHARED=$( { python3 -B Tools/ios-sources.py OpenlistiOS --shared; python3 -B Tools/ios-sources.py OpenlistiOSWidget --shared; } | sort -u)
# Foundation-only helpers that live beside the Mac UI; anything else from
# these folders is Mac UI and must stay out of iOS.
PORTABLE='^openlist/(Editor/OutlinePolicy|Next/NextFormat|Next/Workbench\+TaskFields)\.swift$'
UI=$(grep -E '^openlist/(Next|Views|Editor)/' <<<"$SHARED" | grep -Ev "$PORTABLE" || true)
if [[ -n "$UI" ]]; then
    printf 'The iOS targets must not compile Mac UI files:\n%s\n' "$UI" >&2
    exit 1
fi
while IFS= read -r file; do
    if grep -E '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "$file" | grep -Evq '^[[:space:]]*import Foundation$'; then
        echo "$file is shared with iOS as Foundation-only but imports more" >&2
        exit 1
    fi
done < <(grep -E "$PORTABLE" <<<"$SHARED" || true)
MISSING=$(comm -23 <(find openlist/Model -name '*.swift' | sort) <(python3 -B Tools/ios-sources.py OpenlistiOS --shared | sort))
if [[ -n "$MISSING" ]]; then
    printf 'Add these Model files to Tools/iOS/shared-sources.txt (and run Tools/add-ios-targets.py):\n%s\n' "$MISSING" >&2
    exit 1
fi

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
FLAGS=(-typecheck -sdk "$SDK" -target arm64-apple-ios27.0-simulator -parse-as-library
    -swift-version 6 -default-isolation MainActor
    -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature MemberImportVisibility)
for target in OpenlistiOS OpenlistiOSWidget; do
    SOURCES=()
    while IFS= read -r file; do SOURCES+=("$file"); done < <(python3 -B Tools/ios-sources.py "$target")
    [[ ${#SOURCES[@]} -gt 0 ]] || { echo "No sources for $target" >&2; exit 1; }
    # Debug, Dev and Release compilation conditions (see the project's configurations).
    for conditions in "-DDEBUG" "-DDEBUG -DOPENLIST_DEV" ""; do
        # shellcheck disable=SC2086
        xcrun swiftc "${FLAGS[@]}" $conditions "${SOURCES[@]}"
    done
    echo "Type-checked ${#SOURCES[@]} $target sources for iOS in Debug, Dev and Release"
done
