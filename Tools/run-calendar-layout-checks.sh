#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -O -o "$OUT/calendar-layout-checks" \
    openlist/Views/CalendarOverlapLayout.swift \
    Tools/CalendarLayoutChecks/main.swift
"$OUT/calendar-layout-checks"
