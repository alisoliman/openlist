#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
LEGACY_MODELS=()
for model in openlist/Model/*.swift; do
    case "$model" in
        */Block.swift|*/Inbox*.swift|*/LibraryBackup*.swift) ;;
        *) LEGACY_MODELS+=("$model");;
    esac
done
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -o "$OUT/legacy-inbox" \
  "${LEGACY_MODELS[@]}" Tools/InboxChecks/LegacyBlock.swift Shared/ListAccent.swift Tools/InboxChecks/ReviewSession.swift openlist/Services/MediaStore.swift openlist/Services/BlockTree.swift Tools/InboxChecks/LegacyFixture.swift
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/inbox-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Tools/InboxChecks/ReviewSession.swift Shared/WidgetSnapshot.swift Shared/AppGroup.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Inbox.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift \
  openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift openlist/Services/ActiveTaskPolicy.swift openlist/Services/WidgetSnapshotPublisher.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift openlist/Services/Navigator.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  Tools/EditorChecks/Support.swift Tools/InboxChecks/main.swift
"$OUT/legacy-inbox" "$OUT/Legacy.store"
"$OUT/inbox-checks" "$OUT/Legacy.store" migrate
"$OUT/inbox-checks" "$OUT/Legacy.store" reopen
"$OUT/inbox-checks" "$OUT/Legacy.store" failure
"$OUT/inbox-checks" "$OUT/Legacy.store" verify-failure
