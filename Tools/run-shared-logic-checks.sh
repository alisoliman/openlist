#!/bin/bash
# The UI-free logic the Mac screens and the iOS companion share (Today's set,
# the Inbox queue, the task query language, capture, list page rows and the
# phone's compact wording), with the app targets' concurrency settings. The
# same files type-check for iOS in run-ios-core-checks.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor \
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature MemberImportVisibility -o "$OUT/shared-logic-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/CompactText.swift openlist/Next/NextEditorTypography.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/BlockTree+ListPage.swift openlist/Editor/OutlinePolicy.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/AppSettings.swift openlist/Services/CaptureDraft.swift openlist/Services/NextLibraryCore.swift \
  openlist/Services/TaskQuery.swift openlist/Services/TodayAgenda.swift openlist/Next/NextFormat.swift \
  Tools/EditorChecks/Support.swift Tools/SharedLogicChecks/main.swift
"$OUT/shared-logic-checks"
