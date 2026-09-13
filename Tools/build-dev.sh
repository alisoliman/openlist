#!/bin/bash
# Reproducible local app with a distinct identity and no production data access.
set -euo pipefail
cd "$(dirname "$0")/.."
OPEN_AFTER_BUILD=false
SIGNED_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --open) OPEN_AFTER_BUILD=true ;;
        --signed) SIGNED_BUILD=true ;;
        *) echo "Usage: Tools/build-dev.sh [--open] [--signed]" >&2; exit 1 ;;
    esac
done
mkdir -p build/dev
SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO)
if "$SIGNED_BUILD"; then SIGNING_ARGS=(CODE_SIGNING_ALLOWED=YES); fi
xcodebuild -project openlist.xcodeproj -scheme 'Openlist Dev' -configuration Dev \
    -destination 'platform=macOS' -derivedDataPath build/dev/DerivedData \
    "${SIGNING_ARGS[@]}" build > build/dev/build.log 2>&1 || {
    tail -100 build/dev/build.log
    exit 1
}
APP="$PWD/build/dev/DerivedData/Build/Products/Dev/Openlist Dev.app"
if ! "$SIGNED_BUILD"; then
    # macOS validates team-prefixed groups against the signing identity. An
    # ad-hoc build uses its own private sandbox, never a protected app group.
    python3 - <<'PY'
import plistlib
from pathlib import Path
for source, target in [('Config/OpenlistDev.entitlements', 'build/dev/app.entitlements'),
                       ('Config/OpenlistDevWidget.entitlements', 'build/dev/widget.entitlements')]:
    values = plistlib.loads(Path(source).read_bytes())
    values.pop('com.apple.security.application-groups', None)
    values['com.apple.security.get-task-allow'] = True
    Path(target).write_bytes(plistlib.dumps(values))
PY
    codesign --force --sign - --timestamp=none --options runtime \
        --identifier solimanali.openlist.dev.mcp "$APP/Contents/MacOS/openlist-mcp"
    codesign --force --sign - --timestamp=none --options runtime \
        --entitlements build/dev/widget.entitlements "$APP/Contents/PlugIns/OpenlistWidget.appex"
    codesign --force --sign - --timestamp=none --options runtime \
        --entitlements build/dev/app.entitlements "$APP"
fi
./Tools/verify-dev.sh "$APP"
./Tools/run-dev-isolation-checks.sh
printf 'Built Openlist Dev: %s\n' "$APP"
if "$OPEN_AFTER_BUILD"; then open "$APP"; fi
