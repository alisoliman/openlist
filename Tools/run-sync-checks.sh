#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
FIXTURE_ID=$(uuidgen)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -o "$OUT/legacy-fixture" Tools/SyncChecks/LegacyModels.swift \
  openlist/Model/Recurrence.swift openlist/Services/MediaStore.swift \
  Tools/SyncChecks/ReviewSession.swift Tools/SyncChecks/LegacyFixture.swift
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -o "$OUT/sync-checks" openlist/Model/*.swift Shared/ListAccent.swift Shared/WidgetSnapshot.swift \
  Tools/SyncChecks/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Blocks.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift openlist/Services/Store+Sync.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/InlineMarkdown.swift openlist/Services/MarkdownExportPackage.swift openlist/Services/MarkdownExporter.swift \
  openlist/Services/SyncedTextDraft.swift \
  openlist/Services/ICloudConfiguration.swift openlist/Services/ICloudSyncState.swift openlist/Services/ICloudSyncMonitor.swift openlist/Services/ICloudError.swift \
  openlist/Services/WidgetSnapshotPublisher.swift openlist/Services/ActiveTaskPolicy.swift \
  Tools/CloudSyncChecks/PhaseCheckpoints.swift \
  Tools/EditorChecks/Support.swift Tools/SyncChecks/Checks.swift
trap '"$OUT/sync-checks" "$OUT/Legacy.store" "$FIXTURE_ID" cleanup; rm -rf "$OUT"' EXIT
"$OUT/legacy-fixture" "$OUT/Legacy.store" "$FIXTURE_ID"
"$OUT/sync-checks" "$OUT/Legacy.store" "$FIXTURE_ID" migrate
"$OUT/sync-checks" "$OUT/Legacy.store" "$FIXTURE_ID" reopen
