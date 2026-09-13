#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -DDEBUG -DOPENLIST_DEV -o "$OUT/dev-isolation-checks" \
    Shared/ReviewSession.swift Shared/AppGroup.swift openlist/Services/StoreLocation.swift \
    openlist/Services/MediaStore.swift openlist/Services/AppSettings.swift Tools/DevChecks/main.swift
"$OUT/dev-isolation-checks"
