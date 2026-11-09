#!/bin/bash
# Builds the iOS app, widget, share extension and both test bundles unsigned, runs the unit and
# UI tests on a throwaway iOS 27 simulator, then checks the built bundles. No
# Apple account, signing or iCloud: the build is local-only
# (ICLOUD_CONTAINER_ENVIRONMENT is empty) and tests run in review sessions.
#   OPENLIST_IOS_DEVICE_TYPE   simulator device type (default iPhone 18 Pro)
#   OPENLIST_IOS_DERIVED_DATA  DerivedData directory (default build/ios/DerivedData)
#   OPENLIST_SPM_DIR           shared SwiftPM checkouts (default: inside DerivedData)
#   OPENLIST_IOS_UDID          existing simulator to test on (default: a throwaway one)
#   OPENLIST_IOS_PART          run one part of the tests, 1/3, 2/3 or 3/3, as CI's three
#                              ios jobs do (default: all of them)
set -euo pipefail
cd "$(dirname "$0")/.."
# The UI test classes of the first two parts, about a third of the suite's
# time each, the unit tests going with the first. The third part runs every
# other UI test class, so a new class always runs somewhere.
PART1=(ScreensUITests TaskSwipeUITests ListAppearanceUITests LaunchTests)
PART2=(InteractionUITests PaperAppearanceUITests CaptureTriageUITests TaskDueMenuUITests TaskDetailContextUITests ShellUITests)
SELECT=()
BUNDLES="OpenlistiOSTests OpenlistiOSUITests"
case "${OPENLIST_IOS_PART:-}" in
    "") ;;
    1/3)
        SELECT=(-only-testing:OpenlistiOSTests)
        for class in "${PART1[@]}"; do SELECT+=("-only-testing:OpenlistiOSUITests/$class"); done ;;
    2/3)
        BUNDLES=OpenlistiOSUITests
        for class in "${PART2[@]}"; do SELECT+=("-only-testing:OpenlistiOSUITests/$class"); done ;;
    3/3)
        BUNDLES=OpenlistiOSUITests
        SELECT=(-only-testing:OpenlistiOSUITests)
        for class in "${PART1[@]}" "${PART2[@]}"; do SELECT+=("-skip-testing:OpenlistiOSUITests/$class"); done ;;
    *) echo "OPENLIST_IOS_PART must be 1/3, 2/3 or 3/3" >&2; exit 1 ;;
esac
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
SECONDS=0
xcodebuild "${COMMON[@]}" build-for-testing > "$OUT/build.log" 2>&1 || { tail -100 "$OUT/build.log"; exit 1; }
echo "Built the app and its tests in $((SECONDS / 60)) min $((SECONDS % 60)) s"
if [[ -z "${OPENLIST_IOS_UDID:-}" ]]; then
    # Booted after the build, not before or beside it: on CI's three-core
    # runners a booting or freshly booted simulator slowed the build from
    # two minutes to as many as sixteen.
    SECONDS=0
    xcrun simctl bootstatus "$UDID" -b > "$OUT/boot.log" 2>&1 || { tail -20 "$OUT/boot.log"; exit 1; }
    echo "Booted the simulator in $((SECONDS / 60)) min $((SECONDS % 60)) s"
fi
# From the build's .xctestrun, as the project would have xcodebuild resolve
# its Swift packages again at every launch of the app.
XCTESTRUN=$(ls -t "$DERIVED"/Build/Products/*.xctestrun | sed -n 1p)
# The scheme marks the UI tests serial; turning parallel testing off also
# avoids cloning the simulator for the unit tests.
# A test that fails is run once more, as a loaded runner can time out
# driving the simulator; one that fails twice fails the check. The result
# bundle has what a failure needs, so no sysdiagnose (ten minutes a failure).
SECONDS=0
# Each test's result also goes to the output as it lands, so a run that
# stops short still says how far it got. (Bash 3.2's nounset rejects an
# empty array's expansion, hence the guard.)
xcodebuild -xctestrun "$XCTESTRUN" -destination "id=$UDID" ${SELECT[@]+"${SELECT[@]}"} \
    -parallel-testing-enabled NO -retry-tests-on-failure -test-iterations 2 \
    -collect-test-diagnostics never \
    -resultBundlePath "$OUT/Tests.xcresult" test-without-building 2>&1 | tee "$OUT/test.log" \
    | { grep --line-buffered -E "^Test Case .*(passed|failed) \(|: error: -\[" || true; } \
    | sed -l -E "s/^Test Case '-\[[A-Za-z]+\.([A-Za-z]+) ([A-Za-z0-9_]+)\]' /\1.\2 /" \
    || { tail -100 "$OUT/test.log"; exit 1; }
echo "Ran the tests${OPENLIST_IOS_PART:+ of part $OPENLIST_IOS_PART} in $((SECONDS / 60)) min $((SECONDS % 60)) s"
xcrun xcresulttool get test-results tests --path "$OUT/Tests.xcresult" --compact > "$OUT/tests.json"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/OpenlistiOS.app"
python3 - "$APP" "$OUT/tests.json" "$BUNDLES" <<'PY'
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
def repetitions(case):
    return [child for child in case.get('children', []) if child.get('nodeType') == 'Repetition']
# Passed, or passed on the run it was given after failing once.
def succeeded(case):
    runs = repetitions(case)
    return case.get('result') == 'Passed' or (bool(runs) and runs[-1].get('result') == 'Passed')
passed = 0
retried = []
for name in sys.argv[3].split():
    ran = cases(bundles[name]) if name in bundles else []
    require(ran and all(succeeded(case) for case in ran), f'{name} ran no tests or did not pass')
    passed += len(ran)
    retried += [case.get('nodeIdentifier') or case['name'] for case in ran if len(repetitions(case)) > 1]
# Each needed its second run: a flaky test, to be made deterministic.
for case in retried:
    print(f'Passed only on its second run: {case}')

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
share = app / 'PlugIns/OpenlistiOSShare.appex'
sinfo = plistlib.loads((share / 'Info.plist').read_bytes())
require(sinfo['CFBundleIdentifier'] == 'solimanali.openlist.ios.share', 'share extension identifier')
require(sinfo['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.share-services', 'Share sheet extension')
require(sinfo['NSExtension']['NSExtensionPrincipalClass'] == 'OpenlistiOSShare.ShareViewController', 'share extension entry point')
rule = sinfo['NSExtension']['NSExtensionAttributes']['NSExtensionActivationRule']
require(rule.get('NSExtensionActivationSupportsText') is True and rule.get('NSExtensionActivationSupportsWebURLWithMaxCount') == 1,
        'shares text and a web link')
require((share / 'PrivacyInfo.xcprivacy').is_file(), 'share extension privacy manifest')
# build-for-testing also copies the hosted unit tests into PlugIns.
require(sorted(p.name for p in (app / 'PlugIns').glob('*.appex')) == ['OpenlistiOSShare.appex', 'OpenlistiOSWidget.appex'],
        'only the widget and the share extension are embedded')
again = f' ({len(retried)} on a second run)' if retried else ''
print(f'{passed} iOS tests passed{again}; verified the iPhone-only iOS 27 app, its widget and its share extension')
PY
