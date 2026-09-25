#!/bin/bash
# Renders every widget kind and size from the design's sample data, in light,
# dark and the desktop's in-background rendering, for comparison with the
# design in docs/design/openlist-next-v2/widgets.
#
#   Tools/WidgetPreviews/render.sh                        both fixtures, 2x, into /tmp/widget-previews
#   Tools/WidgetPreviews/render.sh --fixture session --scale 1 --out /tmp/previews
#
# Writes <out>/<fixture>/<mode>/<kind>-<size>.png and <out>/<fixture>/<mode>-sheet.png,
# and for the default fixture agenda-overlap-<size>.png, a meeting over planned slots.
# Not a run-*-checks.sh script, so Tools/check.sh never runs it.
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
WIDGET_SOURCES=()
while IFS= read -r file; do WIDGET_SOURCES+=("$file"); done < <(find OpenlistWidget -name '*.swift' ! -name OpenlistWidgetBundle.swift | sort)
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault -target arm64-apple-macos26.5 \
  -o "$BUILD/widget-previews" \
  Shared/WidgetSnapshot.swift Shared/WidgetActions.swift Shared/WidgetIntents.swift Shared/WidgetRoute.swift \
  Shared/ListAccent.swift Shared/AppGroup.swift Shared/ReviewSession.swift Shared/EmojiSize.swift Shared/ListIcon.swift Shared/ActivityBand.swift \
  "${WIDGET_SOURCES[@]}" Tools/WidgetPreviews/main.swift
"$BUILD/widget-previews" --font Shared/Fonts/InstrumentSerif-Regular.ttf "$@"
