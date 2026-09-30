#!/bin/bash
# Voice capture's reading and filing, without a microphone or a model: what
# was said read into tasks, a model's split grounded in what was said, and
# the tasks heard filed into their lists. `run-voice-audio-checks.sh` runs
# recordings through the real speech model and Apple Intelligence.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor \
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature MemberImportVisibility -o "$OUT/voice-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/CompactText.swift openlist/Next/NextEditorTypography.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/BlockTree+ListPage.swift openlist/Editor/OutlinePolicy.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/AppSettings.swift openlist/Services/CaptureDraft.swift openlist/Services/NextLibraryCore.swift \
  openlist/Services/SpokenCapture.swift openlist/Services/VoiceTaskInterpreter.swift openlist/Next/NextFormat.swift \
  Tools/EditorChecks/Support.swift Tools/VoiceChecks/main.swift
"$OUT/voice-checks"
