#!/bin/bash
# Builds the iOS app, widget and both test bundles unsigned, runs the unit and
# UI tests on a throwaway iOS 27 simulator, then checks the built bundles. No
# Apple account, signing or iCloud: the build is local-only
# (ICLOUD_CONTAINER_ENVIRONMENT is empty) and tests run in review sessions.
#   OPENLIST_IOS_DEVICE_TYPE   simulator device type (default iPhone 18 Pro)
#   OPENLIST_IOS_DERIVED_DATA  DerivedData directory (default build/ios/DerivedData)
#   OPENLIST_SPM_DIR           shared SwiftPM checkouts (default: inside DerivedData)
#   OPENLIST_IOS_UDID          existing simulator to test on (default: a throwaway one)
set -euo pipefail
cd "$(dirname "$0")/.."
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0
DEVICE_TYPE=${OPENLIST_IOS_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro}
OUT=build/ios
DERIVED=${OPENLIST_IOS_DERIVED_DATA:-$OUT/DerivedData}
xcrun simctl list runtimes | grep -q "$RUNTIME" || {
    echo "The iOS 27 simulator runtime is missing. Install it with: xcodebuild -downloadPlatform iOS" >&2
    exit 1
}
rm -rf "$OUT/Tests.xcresult"
mkdir -p "$OUT"
if [[ -n "${OPENLIST_IOS_UDID:-}" ]]; then
    # A booted simulator costs gigabytes; reuse the caller's and leave it alone.
    UDID=$OPENLIST_IOS_UDID
else
    UDID=$(xcrun simctl create "Openlist iOS Checks $$" "$DEVICE_TYPE" "$RUNTIME")
    trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
fi
COMMON=(-project openlist.xcodeproj -scheme OpenlistiOS -configuration Debug
    -destination "id=$UDID" -derivedDataPath "$DERIVED"
    CODE_SIGNING_ALLOWED=NO ICLOUD_CONTAINER_ENVIRONMENT=)
if [[ -n "${OPENLIST_SPM_DIR:-}" ]]; then COMMON+=(-clonedSourcePackagesDirPath "$OPENLIST_SPM_DIR"); fi
xcodebuild "${COMMON[@]}" build-for-testing > "$OUT/build.log" 2>&1 || { tail -100 "$OUT/build.log"; exit 1; }
# The scheme marks the UI tests serial; turning parallel testing off also
# avoids cloning the simulator for the unit tests.
xcodebuild "${COMMON[@]}" -parallel-testing-enabled NO -resultBundlePath "$OUT/Tests.xcresult" \
    test-without-building > "$OUT/test.log" 2>&1 || { tail -100 "$OUT/test.log"; exit 1; }
xcrun xcresulttool get test-results tests --path "$OUT/Tests.xcresult" --compact > "$OUT/tests.json"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/OpenlistiOS.app"
python3 - "$APP" "$OUT/tests.json" <<'PY'
import json, plistlib, sys
from pathlib import Path
app, results = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())
def require(ok, message):
    if not ok:
        raise SystemExit('iOS checks failed: ' + message)

def cases(node):
    if node.get('nodeType') == 'Test Case':
        return [node]
    return [case for child in node.get('children', []) for case in cases(child)]
bundles = {node['name']: node for plan in results['testNodes'] for node in plan.get('children', [])
           if node.get('nodeType', '').endswith('test bundle')}
passed = 0
for name in ('OpenlistiOSTests', 'OpenlistiOSUITests'):
    ran = cases(bundles[name]) if name in bundles else []
    require(ran and all(case.get('result') == 'Passed' for case in ran), f'{name} ran no tests or did not pass')
    passed += len(ran)

info = plistlib.loads((app / 'Info.plist').read_bytes())
require(info['CFBundleIdentifier'] == 'solimanali.openlist.ios', 'app identifier')
require(info.get('CFBundleDisplayName') == 'Openlist', 'display name')
require(info.get('MinimumOSVersion') == '27.0', 'iOS 27 deployment target')
require(info.get('UIDeviceFamily') == [1], 'iPhone only')
orientations = info.get('UISupportedInterfaceOrientations~iphone', info.get('UISupportedInterfaceOrientations'))
require(orientations == ['UIInterfaceOrientationPortrait'], 'portrait only')
require('remote-notification' in info.get('UIBackgroundModes', []), 'CloudKit pushes need remote-notification')
require(info.get('NSSupportsLiveActivities') is True, 'Live Activities')
require(bool(info.get('NSCalendarsFullAccessUsageDescription')), 'calendar usage description')
require(info.get('ITSAppUsesNonExemptEncryption') is False, 'export compliance')
require(info.get('CFBundleURLTypes', [{}])[0].get('CFBundleURLSchemes') == ['openlist'], 'item-link scheme')
# An unsigned build has no CloudKit entitlement, so it must not ask for CloudKit.
require(info.get('OpenlistICloudEnvironment') == '', 'unsigned builds must run local-only')
require('OpenlistReviewSession' not in info and 'OpenlistDevelopment' not in info, 'no review or Dev markers')
require('InstrumentSerif-Regular.ttf' in info.get('UIAppFonts', []) and (app / 'InstrumentSerif-Regular.ttf').is_file(), 'serif font')
require((app / 'PrivacyInfo.xcprivacy').is_file(), 'privacy manifest')
icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')
require((app / 'Assets.car').is_file() and icon == 'Openlist', 'app icon')

widget = app / 'PlugIns/OpenlistiOSWidget.appex'
winfo = plistlib.loads((widget / 'Info.plist').read_bytes())
require(winfo['CFBundleIdentifier'] == 'solimanali.openlist.ios.widget', 'widget identifier')
require(winfo['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', 'WidgetKit extension')
require((widget / 'InstrumentSerif-Regular.ttf').is_file() and (widget / 'PrivacyInfo.xcprivacy').is_file(), 'widget resources')
# build-for-testing also copies the hosted unit tests into PlugIns.
require([p.name for p in (app / 'PlugIns').glob('*.appex')] == ['OpenlistiOSWidget.appex'], 'only the widget is embedded')
print(f'{passed} iOS tests passed; verified the iPhone-only iOS 27 app and its embedded widget')
PY
