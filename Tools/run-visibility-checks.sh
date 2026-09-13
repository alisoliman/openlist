#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
    -swift-version 6 -default-isolation MainActor \
    -o "$OUT/visibility-checks" \
    openlist/Model/Block.swift \
    openlist/Model/BlockKind.swift \
    openlist/Model/Recurrence.swift \
    openlist/Model/CalendarTypes.swift \
    openlist/Model/TaskList.swift \
    Shared/ListAccent.swift \
    openlist/Services/ActiveTaskPolicy.swift \
    Tools/VisibilityChecks/main.swift

"$OUT/visibility-checks"
