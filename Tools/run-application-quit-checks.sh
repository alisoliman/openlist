#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/application-quit-checks" \
  openlist/Services/ApplicationQuit.swift Tools/ApplicationQuitChecks/main.swift
python3 - "$OUT/application-quit-checks" <<'PY'
import subprocess
import sys

for mode in ("accept", "retry"):
    result = subprocess.run([sys.argv[1], mode], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "cancelled request preserved app" in result.stdout, result.stdout
    assert "delegate reply true" in result.stdout and "quit completed" in result.stdout, result.stdout
    if mode == "retry":
        assert "delegate reply false" in result.stdout and "delegate attempt 2" in result.stdout, result.stdout
print("2 headless AppKit quit workflows passed (cancel guard, async delegate reply, failed-save retry)")
PY
