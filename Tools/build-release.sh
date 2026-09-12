#!/bin/bash
# Build without credentials. Signing and packaging are separate, explicit steps.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?Usage: build-release.sh VERSION BUILD_NUMBER}
BUILD_NUMBER=${2:?Usage: build-release.sh VERSION BUILD_NUMBER}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected version X.Y.Z" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "Expected positive build number" >&2; exit 1; }
[[ $(uname -m) == arm64 ]] || { echo "Use an Apple Silicon build host" >&2; exit 1; }
mkdir -p build/release
xcodebuild -project openlist.xcodeproj -scheme openlist -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/release/DerivedData \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build \
    > build/release/build.log 2>&1 || { tail -100 build/release/build.log; exit 1; }
APP=build/release/DerivedData/Build/Products/Release/openlist.app
./Tools/verify-release.sh "$APP" "$VERSION" "$BUILD_NUMBER"
