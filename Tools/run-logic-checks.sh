#!/bin/bash
# Compiles the app's own logic sources against a set of assertions and runs
# them. No Xcode target needed.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# 1. Date parsing, recurrence, the change log's writes and saved changes — Foundation only.
xcrun swiftc \
    -swift-version 6 -O \
    -o "$OUT/logic-checks" \
    openlist/Model/Recurrence.swift \
    openlist/Services/RegexCache.swift \
    openlist/Services/DateParser.swift \
    openlist/Services/RecurrenceEngine.swift \
    openlist/Next/NextLogWrites.swift \
    openlist/Next/NextSavedChanges.swift \
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

# 3. SwiftUI's text line, which the Next UI's line boxes are fitted over — needs AppKit and SwiftUI.
xcrun swiftc \
    -swift-version 6 -O \
    -o "$OUT/line-height-checks" \
    openlist/Next/NextTextLine.swift \
    Tools/LineHeightChecks/main.swift

"$OUT/logic-checks"
"$OUT/text-checks"
"$OUT/line-height-checks"
