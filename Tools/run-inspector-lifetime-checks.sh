#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
export OPENLIST_COPY_CHECK_ID="inspector-lifetime-$(uuidgen)"
COPY_MEDIA_DIR="$HOME/Library/Application Support/Openlist-Review-$OPENLIST_COPY_CHECK_ID"
trap 'rm -rf "$OUT" "$COPY_MEDIA_DIR"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/inspector-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Tools/ReusableCopyChecks/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift \
  openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Views/TaskInspectorMetadata.swift openlist/Views/LabelPicker.swift openlist/Views/AttachmentRow.swift \
  openlist/Editor/TaskMetadataChips.swift openlist/Editor/MetadataFlowLayout.swift \
  openlist/Editor/BlockRowView.swift openlist/Editor/BlockTextView.swift openlist/Editor/MarkdownInputRules.swift \
  openlist/Editor/SlashMenuLayout.swift openlist/Views/TaskDetailButton.swift \
  Tools/EditorChecks/Support.swift Tools/InspectorLifetimeChecks/LifetimeSupport.swift Tools/InspectorLifetimeChecks/main.swift
"$OUT/inspector-checks"
