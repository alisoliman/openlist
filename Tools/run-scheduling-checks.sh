#!/bin/bash
# Calendar planning regression scenarios use the production Foundation sources.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -O -o "$OUT/scheduling-checks" \
    openlist/Model/CalendarTypes.swift \
    openlist/Services/AdaptiveScheduler.swift \
    Tools/SchedulingChecks/main.swift
"$OUT/scheduling-checks"
