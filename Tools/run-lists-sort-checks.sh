#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
    -swift-version 6 -default-isolation MainActor \
    -o "$OUT/lists-sort-checks" \
    openlist/Model/TaskList.swift openlist/Model/TrashMetadata.swift \
    openlist/Model/ListGallerySorting.swift \
    Shared/ListAccent.swift \
    openlist/Views/ListGallerySortMenu.swift \
    Tools/ListsSortChecks/main.swift

"$OUT/lists-sort-checks"
