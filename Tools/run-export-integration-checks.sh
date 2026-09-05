#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/export-integration-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Tools/ExportIntegrationChecks/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Blocks.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/InlineMarkdown.swift openlist/Services/MarkdownExportPackage.swift \
  openlist/Services/MarkdownExporter.swift \
  Tools/EditorChecks/Support.swift Tools/ExportIntegrationChecks/main.swift
"$OUT/export-integration-checks"
