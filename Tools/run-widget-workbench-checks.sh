#!/bin/bash
# Drives the widget command processor through the app's own Workbench, so a
# widget's tick, Start, Pause, Resume and Done are checked as the window takes
# them. It builds the whole app target, apart from the MCP server's package
# and the app's entry point, so it is the slowest suite to compile.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find openlist Shared -name '*.swift' \
    ! -name MCPIntegration.swift ! -name MCPStoreAdapter.swift ! -name MCPTools.swift ! -name openlistApp.swift \
    ! -path Shared/ReviewSession.swift ! -path Shared/AppGroup.swift | sort)
# The app target's own concurrency settings. The app's build reports its
# warnings; this one would only repeat them.
xcrun swiftc -swift-version 6 -default-isolation MainActor -suppress-warnings \
    -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature MemberImportVisibility -target arm64-apple-macos27.0 \
    -o "$OUT/widget-workbench-checks" "${SOURCES[@]}" Tools/WidgetWorkbenchChecks/*.swift
mkdir "$OUT/container"
"$OUT/widget-workbench-checks" "$OUT/container" "$(uuidgen)"
