#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/capture-selection-checks" \
  openlist/Views/CaptureTitleField.swift Tools/CaptureSelectionChecks/main.swift
"$OUT/capture-selection-checks"
