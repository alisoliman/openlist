#!/bin/bash
# Requires a Developer ID identity, app provisioning profile, and notary credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?Usage: package-release.sh VERSION BUILD_NUMBER}
BUILD_NUMBER=${2:?Missing build number}
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
: "${APP_PROVISION_PROFILE:?Set APP_PROVISION_PROFILE to the original Developer ID app .provisionprofile}"
APP=build/release/DerivedData/Build/Products/Release/openlist.app
./Tools/verify-release.sh "$APP" "$VERSION" "$BUILD_NUMBER"
NOTARY_ARGS=()
if [[ -n ${NOTARY_PROFILE:-} ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
else
    : "${NOTARY_KEY_PATH:?Set NOTARY_PROFILE or NOTARY_KEY_PATH}"
    : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
    : "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID}"
    NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi
SIGNING_DIR=build/release/signing
python3 -B Tools/prepare-release-signing.py prepare \
    --profile "$APP_PROVISION_PROFILE" \
    --source-entitlements Config/openlist.entitlements \
    --app "$APP" --output-entitlements "$SIGNING_DIR/openlist.entitlements"
for component in OpenlistWidget openlist; do
    bundle="$APP"
    entitlements="$SIGNING_DIR/openlist.entitlements"
    [[ "$component" == openlist ]] || bundle="$APP/Contents/PlugIns/OpenlistWidget.appex"
    [[ "$component" == openlist ]] || entitlements="Config/OpenlistWidget.entitlements"
    codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" \
        --entitlements "$entitlements" "$bundle"
done
codesign --verify --deep --strict --verbose=2 "$APP"
# Refuse development/ad-hoc signatures even when an incorrect identity was supplied.
SIGNATURE_INFO=$(codesign -dvv "$APP" 2>&1)
[[ "$SIGNATURE_INFO" == *"Authority=Developer ID Application:"* ]] || {
    echo "Release requires a Developer ID Application signature" >&2; exit 1
}
codesign --display --entitlements - --xml "$APP" > "$SIGNING_DIR/signed-entitlements.plist"
# This option's optional argument requires '='; a separate prefix is a code path.
codesign --display --extract-certificates="$SIGNING_DIR/signing-cert-" "$APP"
python3 -B Tools/prepare-release-signing.py verify \
    --profile "$APP/Contents/embedded.provisionprofile" \
    --source-entitlements Config/openlist.entitlements \
    --signed-entitlements "$SIGNING_DIR/signed-entitlements.plist" \
    --signing-certificate "$SIGNING_DIR/signing-cert-0"
mkdir -p dist
STEM="Openlist-$VERSION-macos-arm64"
SUBMISSION="build/release/notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" "${NOTARY_ARGS[@]}" --wait --timeout 20m \
    --output-format json > build/release/notarization.json
python3 -c 'import json; r=json.load(open("build/release/notarization.json")); print(r); assert r["status"] == "Accepted", "Notarization was not accepted"'
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$STEM.zip"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/openlist.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/LICENSE.txt"
hdiutil create -volname "Openlist $VERSION" -srcfolder "$STAGING" -ov -format UDZO "dist/$STEM.dmg"
codesign --timestamp --sign "$SIGNING_IDENTITY" "dist/$STEM.dmg"
xcrun notarytool submit "dist/$STEM.dmg" "${NOTARY_ARGS[@]}" --wait --timeout 20m \
    --output-format json > build/release/dmg-notarization.json
python3 -c 'import json; r=json.load(open("build/release/dmg-notarization.json")); print(r); assert r["status"] == "Accepted", "DMG notarization was not accepted"'
xcrun stapler staple "dist/$STEM.dmg"
xcrun stapler validate "dist/$STEM.dmg"
hdiutil verify "dist/$STEM.dmg"
(cd dist && shasum -a 256 "$STEM.zip" "$STEM.dmg" > SHA256SUMS.txt)
echo "Signed and notarized release packages are in dist/"
