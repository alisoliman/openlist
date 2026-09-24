#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/bulk-action-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift openlist/Next/NextEditorTypography.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+BulkActions.swift openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Editor/BlockTextView.swift openlist/Editor/MarkdownInputRules.swift openlist/Editor/SlashMenuLayout.swift \
  Tools/EditorChecks/Support.swift Tools/BulkActionChecks/TrashChecks.swift Tools/BulkActionChecks/NestedOwnerChecks.swift Tools/BulkActionChecks/main.swift
"$OUT/bulk-action-checks" "$OUT/Bulk.store"
"$OUT/bulk-action-checks" "$OUT/Bulk.store" reopen
