#!/bin/bash
# Uses an existing development signature/profile; never accesses the real store
# or the Production CloudKit database. Not part of credential-free CI.
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE_APP=${1:?Usage: run-cloud-sync-checks.sh DEVELOPMENT_APP MODE [RETAINED_DIRECTORY]}
MODE=${2:?Choose an explicit verification mode}
case "$MODE" in
    --account-only|--connection|--initialize-schema|--run) ;;
    --cleanup|--resume) [[ $# == 3 ]] || { echo "$MODE requires a retained diagnostic directory" >&2; exit 1; } ;;
    *) echo "Unsupported verification mode" >&2; exit 1 ;;
esac
test -f "$SOURCE_APP/Contents/embedded.provisionprofile" || {
    echo "The supplied app has no embedded provisioning profile" >&2; exit 1
}
codesign --verify --deep --strict "$SOURCE_APP"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
APP="$OUT/Openlist iCloud Checks.app"
mkdir -p "$APP/Contents/MacOS"
cp Tools/CloudSyncChecks/Info.plist "$APP/Contents/Info.plist"
cp "$SOURCE_APP/Contents/embedded.provisionprofile" "$APP/Contents/embedded.provisionprofile"
codesign -d --entitlements :- "$SOURCE_APP" > "$OUT/entitlements.plist" 2>"$OUT/signature.log" || {
    cat "$OUT/signature.log" >&2; exit 1
}
[[ $(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-environment' "$OUT/entitlements.plist") == Development ]] || {
    echo "Refusing to use a Production iCloud signature" >&2; exit 1
}
codesign -d --extract-certificates="$OUT/signing-" "$SOURCE_APP"
IDENTITY=$(openssl x509 -inform DER -in "$OUT/signing-0" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -target arm64-apple-macos26.5 -o "$APP/Contents/MacOS/CloudSyncChecks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/AppGroup.swift \
  openlist/Services/MediaStore.swift openlist/Services/ICloudConfiguration.swift openlist/Services/ICloudError.swift \
  Tools/CloudSyncChecks/PhaseCheckpoints.swift Tools/CloudSyncChecks/Checks.swift
codesign --force --sign "$IDENTITY" --entitlements "$OUT/entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP"
# Use a normal app lifecycle for daemon-backed transfers. Launch headlessly
# without replacing or bringing forward the user's running app.
run_check() {
    : > "$OUT/stdout.log"
    : > "$OUT/stderr.log"
    open -n -g -W --stdout "$OUT/stdout.log" --stderr "$OUT/stderr.log" "$APP" --args "$@"
    cat "$OUT/stdout.log"
    if ! grep -qx 'RESULT: success' "$OUT/stdout.log"; then
        cat "$OUT/stderr.log" >&2
        return 1
    fi
}
if [[ "$MODE" == --run || "$MODE" == --resume ]]; then
    if [[ "$MODE" == --run ]]; then
        run_check --seed
        FIXTURE_ROOT=$(sed -n 's/^SEEDED_ROOT: //p' "$OUT/stdout.log")
    else
        FIXTURE_ROOT=$3
    fi
    [[ -n "$FIXTURE_ROOT" ]] || { echo "Offline fixture path was not reported" >&2; exit 1; }
    for phase in --upload --download-edit --verify-edit-delete --verify-deletion; do
        run_check "$phase" "$FIXTURE_ROOT"
    done
else
    run_check "$MODE" "${@:3}"
fi
