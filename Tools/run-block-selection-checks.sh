#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/block-selection-checks" \
  openlist/Model/BlockSelection.swift Tools/BlockSelectionChecks/main.swift
"$OUT/block-selection-checks"
