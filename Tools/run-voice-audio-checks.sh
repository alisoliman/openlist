#!/bin/bash
# Recordings through voice capture end to end: the on-device speech model,
# Apple Intelligence where this Mac has it, and the tasks filed into their
# lists. Needs macOS 27 and the speech model for your language (fetched on
# first use); it isn't part of check.sh because CI has neither. Set
# OPENLIST_VOICE_RECORDINGS to a folder of your own recordings, named as the
# scenarios in Tools/VoiceAudioChecks/main.swift, to try real voices.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor \
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature MemberImportVisibility -o "$OUT/voice-audio-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/CompactText.swift openlist/Next/NextEditorTypography.swift \
  openlist/Services/Store.swift openlist/Services/Store+Trash.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/BlockTree+ListPage.swift openlist/Editor/OutlinePolicy.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  openlist/Services/AppSettings.swift openlist/Services/CaptureDraft.swift openlist/Services/NextLibraryCore.swift \
  openlist/Services/SpokenCapture.swift openlist/Services/VoiceTaskInterpreter.swift openlist/Services/VoiceListener.swift \
  openlist/Services/VoiceCapture.swift openlist/Next/NextFormat.swift \
  Tools/EditorChecks/Support.swift Tools/VoiceAudioChecks/main.swift
"$OUT/voice-audio-checks"
