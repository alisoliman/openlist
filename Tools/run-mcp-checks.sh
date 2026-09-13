#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tmp
export TMPDIR="$PWD/.build/tmp"
BUILD_OPTIONS=(--configuration debug)
# Keep this nonempty for macOS Bash 3.2's nounset handling of array expansion.
CHECK_FLAGS=(-DOPENLIST_CHECKS)
if [[ "${OPENLIST_DEV_CHECKS:-0}" == 1 ]]; then CHECK_FLAGS+=(-DDEBUG -DOPENLIST_DEV); fi
if [[ -n "${OPENLIST_SWIFT_BUILD_SYSTEM:-}" ]]; then
    case "$OPENLIST_SWIFT_BUILD_SYSTEM" in
        native|swiftbuild) BUILD_OPTIONS+=(--build-system "$OPENLIST_SWIFT_BUILD_SYSTEM") ;;
        *) echo "Unsupported Swift build system" >&2; exit 1 ;;
    esac
fi
swift test "${BUILD_OPTIONS[@]}" > .build/mcp-transport.log 2>&1 || { tail -100 .build/mcp-transport.log; exit 1; }
tail -8 .build/mcp-transport.log
swift build "${BUILD_OPTIONS[@]}" --product OpenlistMCP > .build/mcp-library.log 2>&1 || { tail -100 .build/mcp-library.log; exit 1; }
./Tools/update-mcp-notices.sh .build/checkouts --check
BIN=$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)
OUT=$(mktemp -d "$TMPDIR/mcp-store-checks.XXXXXX")
trap 'rm -rf "$OUT"' EXIT

# Support both SwiftPM's native and newer Swift Build output layouts.
FLAGS=(-I "$BIN" -I "$BIN/Modules" -L "$BIN" -lOpenlistMCP)
for directory in .build/checkouts/swift-atomics/Sources/_AtomicsShims/include \
    .build/checkouts/swift-system/Sources/CSystem/include \
    .build/checkouts/swift-nio/Sources/CNIOWindows/include; do
    FLAGS+=(-I "$directory")
done
if [[ "$BIN" == "$PWD/.build/out/Products/"* ]]; then
    for map in .build/out/Intermediates.noindex/GeneratedModuleMaps/CNIO*.modulemap; do
        FLAGS+=(-Xcc "-fmodule-map-file=$map")
    done
else
    while IFS= read -r map; do FLAGS+=(-Xcc "-fmodule-map-file=$map"); done \
        < <(find "$BIN" -path '*/C*.build/module.modulemap' -type f)
fi
xcrun swiftc -swift-version 6 -default-isolation MainActor -enable-upcoming-feature MemberImportVisibility "${FLAGS[@]}" "${CHECK_FLAGS[@]}" -o "$OUT/mcp-store-checks" \
    openlist/Model/*.swift Shared/ListAccent.swift Shared/AppGroup.swift Tools/MCPChecks/ReviewSession.swift openlist/Design/Theme.swift \
    openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Inbox.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
    openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
    openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
    openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
    openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
    openlist/Services/ActiveTaskPolicy.swift openlist/Services/AppSettings.swift \
    openlist/Services/MCPTools.swift openlist/Services/MCPStoreAdapter.swift \
    openlist/Services/MCPTokenStore.swift openlist/Services/MCPIntegration.swift \
    Tools/EditorChecks/Support.swift Tools/MCPChecks/HelperRoundTrip.swift Tools/MCPChecks/main.swift
HELPER=${OPENLIST_MCP_HELPER:-"$OUT/openlist-mcp"}
if [[ -z "${OPENLIST_MCP_HELPER:-}" ]]; then
    xcrun swiftc -swift-version 6 -parse-as-library "${CHECK_FLAGS[@]}" -o "$HELPER" OpenlistMCPHelper/*.swift
fi
[[ -x "$HELPER" ]] || { echo "MCP helper is missing: $HELPER" >&2; exit 1; }
FIXTURE_ID=$(uuidgen)
"$OUT/mcp-store-checks" "$OUT/MCP.store" "$FIXTURE_ID" prepare "$HELPER"
"$OUT/mcp-store-checks" "$OUT/MCP.store" "$FIXTURE_ID" reopen "$HELPER"
