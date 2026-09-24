#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/widget-checks" \
    Shared/WidgetSnapshot.swift Shared/WidgetActions.swift Shared/WidgetRoute.swift Shared/ListAccent.swift \
    Shared/AppGroup.swift Shared/ReviewSession.swift Shared/EmojiSize.swift Shared/ListIcon.swift Shared/ActivityBand.swift \
    OpenlistWidget/WidgetModels.swift OpenlistWidget/SnapshotOverlay.swift OpenlistWidget/SampleData.swift \
    openlist/Model/LocalLink.swift Tools/WidgetChecks/main.swift
# The design's clock: 23 September 2026 in a fixed zone.
TZ=Europe/Amsterdam "$OUT/widget-checks"
