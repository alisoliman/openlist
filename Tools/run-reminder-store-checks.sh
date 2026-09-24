#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/reminder-store-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/ReminderNotificationClient.swift openlist/Services/ReminderRecovery.swift openlist/Services/ReminderNavigation.swift openlist/Services/Navigator.swift \
  Tools/ReminderChecks/FakeClient.swift Tools/ReminderStoreChecks/Support.swift Tools/ReminderStoreChecks/main.swift
"$OUT/reminder-store-checks" "$OUT/Library.store" write
"$OUT/reminder-store-checks" "$OUT/Library.store" reopen
