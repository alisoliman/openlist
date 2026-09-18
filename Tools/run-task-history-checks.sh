#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -o "$OUT/legacy-history-fixture" \
  Tools/TaskHistoryChecks/LegacyFixture.swift
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/task-history-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift \
  openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift openlist/Services/Navigator.swift openlist/Services/DragPayload.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/SampleData.swift Tools/EditorChecks/Support.swift Tools/TaskHistoryChecks/main.swift
"$OUT/task-history-checks" "$OUT/History.store" write
"$OUT/task-history-checks" "$OUT/History.store" reopen
"$OUT/task-history-checks" "$OUT/History.store" verify-clear
"$OUT/legacy-history-fixture" "$OUT/LegacyHistory.store"
"$OUT/task-history-checks" "$OUT/LegacyHistory.store" legacy
