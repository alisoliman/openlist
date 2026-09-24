#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -O -o "$OUT/export-checks" \
    openlist/Model/BlockKind.swift \
    Shared/ListAccent.swift \
    openlist/Next/NextEditorTypography.swift \
    openlist/Services/RichTextCodec.swift \
    openlist/Services/InlineMarkdown.swift \
    openlist/Services/MarkdownExportPackage.swift \
    Tools/ExportChecks/main.swift
"$OUT/export-checks"
