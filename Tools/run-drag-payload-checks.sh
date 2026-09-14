#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/drag-payload-checks" \
  openlist/Services/DragPayload.swift Tools/DragPayloadChecks/main.swift
"$OUT/drag-payload-checks"
for plist in Config/Openlist-Info.plist Config/OpenlistDev-Info.plist; do
    python3 Tools/verify-drag-types.py "$plist" source
done
