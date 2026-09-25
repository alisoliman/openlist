#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/widget-action-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/WidgetSnapshot.swift Shared/WidgetCommand.swift Shared/WidgetLink.swift Shared/WidgetKind.swift \
  Tools/WidgetActionChecks/ReviewSession.swift openlist/Next/NextEditorTypography.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/AdaptiveScheduler.swift openlist/Services/ExternalCalendarSource.swift \
  openlist/Services/MacWorkMonitor.swift openlist/Services/CalendarCoordinator.swift openlist/Services/AppSettings.swift \
  openlist/Services/ActiveTaskPolicy.swift \
  openlist/Services/WidgetSnapshotPublisher.swift openlist/Services/WidgetCalendarBridge.swift \
  openlist/Services/Navigator.swift openlist/Services/QuickCaptureRequest.swift openlist/Services/NoteItemLink.swift \
  openlist/Services/WidgetCommandProcessor.swift openlist/Services/WidgetLinkRouter.swift \
  Tools/EditorChecks/Support.swift Tools/WidgetActionChecks/main.swift
"$OUT/widget-action-checks" "$OUT" "$(uuidgen)"
