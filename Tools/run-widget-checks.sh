#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
FIXTURE=$(uuidgen)
trap 'rm -rf "$OUT" "${TMPDIR:-/tmp}/OpenlistUIReviews/WidgetChecks-$FIXTURE"' EXIT

# The widget target's own concurrency settings, so isolation mistakes that
# Xcode would reject fail here too.
xcrun swiftc -swift-version 6 -default-isolation MainActor \
    -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature MemberImportVisibility -target arm64-apple-macos27.0 \
    -o "$OUT/widget-checks" \
    Shared/WidgetSnapshot.swift Shared/WidgetCommand.swift Shared/WidgetLink.swift Shared/AppGroup.swift Shared/ListAccent.swift Shared/ListIcon.swift Shared/ActivityBand.swift \
    Tools/WidgetChecks/ReviewSession.swift \
    OpenlistWidget/Model/*.swift OpenlistWidget/Timeline/TimelineSchedule.swift \
    OpenlistWidget/Design/WidgetStyle.swift OpenlistWidget/Design/WidgetFonts.swift \
    Tools/WidgetChecks/main.swift

"$OUT/widget-checks" "$FIXTURE"
