#!/bin/bash
# Compiles the app's own logic sources against a set of assertions and runs
# them. No Xcode target needed.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# 1. Date parsing and recurrence — Foundation only.
xcrun swiftc \
    -swift-version 6 -O \
    -o "$OUT/logic-checks" \
    openlist/Model/Recurrence.swift \
    openlist/Services/RegexCache.swift \
    openlist/Services/DateParser.swift \
    openlist/Services/RecurrenceEngine.swift \
    Tools/LogicChecks/main.swift

# 2. Rich-text splicing — needs AppKit and the theme's font metrics.
xcrun swiftc \
    -swift-version 6 -O \
    -o "$OUT/text-checks" \
    openlist/Model/BlockKind.swift \
    Shared/ListAccent.swift \
    openlist/Next/NextEditorTypography.swift \
    openlist/Services/RichTextCodec.swift \
    Tools/TextChecks/main.swift

"$OUT/logic-checks"
"$OUT/text-checks"
