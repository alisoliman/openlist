#!/bin/bash
# Decodes rich text the iPhone wrote (Tools/RichTextParityChecks/Fixtures,
# made on an iOS simulator by Tools/make-rich-text-fixtures.sh) with the
# Mac's codec, so a change on either side that stops the two devices
# agreeing on bold, italic, code, links or strikethrough fails here.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/rich-text-parity-checks" \
  openlist/Model/BlockKind.swift openlist/Next/NextEditorTypography.swift openlist/Services/RichTextCodec.swift \
  Tools/RichTextParityChecks/Samples.swift Tools/RichTextParityChecks/main.swift
"$OUT/rich-text-parity-checks" "$@"
