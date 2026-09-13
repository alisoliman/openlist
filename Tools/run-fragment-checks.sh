#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
export OPENLIST_COPY_CHECK_ID="fragment-$(uuidgen)"
COPY_MEDIA_DIR="$HOME/Library/Application Support/Openlist-Review-$OPENLIST_COPY_CHECK_ID"
trap 'rm -rf "$OUT" "$COPY_MEDIA_DIR"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/fragment-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Tools/ReusableCopyChecks/ReviewSession.swift openlist/Design/Theme.swift \
  openlist/Services/Store.swift openlist/Services/Store+Inbox.swift openlist/Services/Store+Activity.swift openlist/Services/Store+Blocks.swift openlist/Services/Store+Copies.swift openlist/Services/Store+Sync.swift \
  openlist/Services/Store+Tasks.swift openlist/Services/Store+LabelMerge.swift openlist/Services/Store+Calendar.swift \
  openlist/Services/Store+CompletionUndo.swift openlist/Services/Store+Capture.swift \
  openlist/Services/BlockTree.swift openlist/Services/RichTextCodec.swift \
  openlist/Services/MediaStore.swift openlist/Services/EditorUndo.swift \
  openlist/Services/DateParser.swift openlist/Services/RegexCache.swift openlist/Services/RecurrenceEngine.swift \
  Tools/EditorChecks/Support.swift openlist/Services/FragmentContent.swift openlist/Services/FragmentMarkdown.swift openlist/Services/FragmentClipboard.swift openlist/Services/Store+Fragments.swift openlist/Services/InlineMarkdown.swift openlist/Editor/MarkdownInputRules.swift Tools/FragmentChecks/main.swift
"$OUT/fragment-checks" "$OUT/Copies.store" write
"$OUT/fragment-checks" "$OUT/Copies.store" reopen
