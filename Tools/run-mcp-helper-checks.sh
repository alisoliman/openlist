#!/bin/bash
# Isolated native launcher checks; never build, launch, or open data from the app.
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="Tools/MCPHelperChecks/.build-$$"
mkdir "$CHECK_DIR"
trap 'rm -rf -- "$CHECK_DIR"' EXIT
export TMPDIR="$PWD/$CHECK_DIR"
xcrun swiftc -swift-version 6 -warnings-as-errors -parse-as-library -O \
    -target arm64-apple-macos26.5 \
    -module-cache-path "$CHECK_DIR/module-cache" \
    OpenlistMCPHelper/*.swift -o "$CHECK_DIR/openlist-mcp"
python3 -B Tools/MCPHelperChecks/check_bridge.py "$CHECK_DIR/openlist-mcp" "$CHECK_DIR"
