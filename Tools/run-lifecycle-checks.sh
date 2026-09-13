#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/lifecycle-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Tools/LifecycleChecks/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  Tools/EditorChecks/Support.swift Tools/LifecycleChecks/main.swift
FIXTURE_ID=$(uuidgen)
trap '"$OUT/lifecycle-checks" "$OUT/Lifecycle.store" "$FIXTURE_ID" cleanup >/dev/null 2>&1 || true; rm -rf "$OUT"' EXIT
"$OUT/lifecycle-checks" "$OUT/Lifecycle.store" "$FIXTURE_ID" prepare
"$OUT/lifecycle-checks" "$OUT/Lifecycle.store" "$FIXTURE_ID" reopen
"$OUT/lifecycle-checks" "$OUT/Lifecycle.store" "$FIXTURE_ID" verify-reset
