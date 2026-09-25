#!/bin/bash
# Renders widget views to PNGs, drawn on the design's desktop. Every case is
# drawn twice: at the design's sizes, to compare with the mockup crops,
#   build/widget-renders/<kind>-<size>[-<state>]-<mode>.png
# and at the smaller sizes macOS gives widgets (164, 344 x 164, 344 x 344,
# 704 x 344), where fixed columns truncate what shares their row:
#   build/widget-renders/<kind>-<size>-real[-<state>]-<mode>.png
#
#   ./Tools/render-widgets.sh                 every kind, both sizes
#   ./Tools/render-widgets.sh today upnext    just these
#   ./Tools/render-widgets.sh --real today    just the measured sizes (or --design)
#
# Kinds: today upnext quickadd (or capture) list agenda summary activity.
# Only the requested widget files are compiled, so one kind renders even while
# another is broken. A development tool; not part of check.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

ALL=(today upnext quickadd list agenda summary activity)
KINDS=()
# Empty for both sizes.
CANVAS=""
for arg in "$@"; do
    case "$arg" in
        --design) CANVAS=design ;;
        --real) CANVAS=real ;;
        *) KINDS+=("$arg") ;;
    esac
done
[ ${#KINDS[@]} -eq 0 ] && KINDS=("${ALL[@]}")

OUT_DIR=build/widget-renders
BIN=$(mktemp -d)
trap 'rm -rf "$BIN"' EXIT

FILES=()
FLAGS=()
for kind in "${KINDS[@]}"; do
    case "$kind" in
        today) type=Today; prefix=today ;;
        upnext) type=UpNext; prefix=upnext ;;
        quickadd|capture) type=QuickAdd; prefix=capture ;;
        list) type=List; prefix=list ;;
        agenda) type=Agenda; prefix=agenda ;;
        summary) type=Summary; prefix=summary ;;
        activity) type=Activity; prefix=activity ;;
        *) echo "Unknown kind: $kind (expected: ${ALL[*]})" >&2; exit 2 ;;
    esac
    FILES+=("OpenlistWidget/Widgets/${type}Widget.swift")
    FLAGS+=("-DRENDER_$(echo "$type" | tr '[:lower:]' '[:upper:]')")
    mkdir -p "$OUT_DIR"
    # Only the sizes being redrawn, so the other set stays to compare with.
    case "$CANVAS" in
        design) find "$OUT_DIR" -name "$prefix-*.png" ! -name "$prefix-*-real*.png" -delete ;;
        real) rm -f "$OUT_DIR/$prefix"-*-real*.png ;;
        *) rm -f "$OUT_DIR/$prefix"-*.png ;;
    esac
done

xcrun swiftc -swift-version 6 -default-isolation MainActor \
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature MemberImportVisibility -target arm64-apple-macos27.0 \
  -DWIDGET_RENDER "${FLAGS[@]}" -o "$BIN/widget-render" \
  Shared/*.swift OpenlistWidget/Design/*.swift OpenlistWidget/Model/*.swift \
  OpenlistWidget/Timeline/*.swift OpenlistWidget/Intents/*.swift \
  "${FILES[@]}" Tools/WidgetRender/*.swift

"$BIN/widget-render" "$OUT_DIR" Shared/Fonts/InstrumentSerif-Regular.ttf $CANVAS
