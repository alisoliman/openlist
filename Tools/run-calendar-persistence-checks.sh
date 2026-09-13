#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
FIXTURE_ID=$(uuidgen)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -o "$OUT/legacy-calendar-fixture" \
  Tools/CalendarPersistenceChecks/Legacy/*.swift Tools/CalendarPersistenceChecks/LegacyFixture.swift \
  openlist/Model/ActivityEvent.swift openlist/Model/TaskActivityChange.swift openlist/Model/Attachment.swift openlist/Model/BlockKind.swift \
  openlist/Model/Recurrence.swift openlist/Model/SidebarSection.swift openlist/Model/TaskLabel.swift \
  Shared/ListAccent.swift openlist/Services/MediaStore.swift Tools/LifecycleChecks/ReviewSession.swift
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -o "$OUT/calendar-persistence-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Tools/LifecycleChecks/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Inbox.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/ICloudConfiguration.swift openlist/Services/ICloudError.swift \
  Tools/EditorChecks/Support.swift Tools/CalendarPersistenceChecks/Checks.swift Tools/CalendarPersistenceChecks/CompletionChecks.swift
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -o "$OUT/legacy-completion-fixture" \
  Tools/CalendarPersistenceChecks/LegacyCompletionFixture.swift
"$OUT/legacy-calendar-fixture" "$OUT/Calendar.store" "$FIXTURE_ID"
"$OUT/calendar-persistence-checks" "$OUT/Calendar.store" "$FIXTURE_ID" migrate
"$OUT/calendar-persistence-checks" "$OUT/Calendar.store" "$FIXTURE_ID" reopen
"$OUT/calendar-persistence-checks" "$OUT/Calendar.store" "$FIXTURE_ID" verify-reset
"$OUT/legacy-completion-fixture" "$OUT/LegacyCompletion.store"
"$OUT/calendar-persistence-checks" "$OUT/LegacyCompletion.store" "$FIXTURE_ID" legacy-completion
