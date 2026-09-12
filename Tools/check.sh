#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for suite in logic editor duplication export export-integration lifecycle visibility mcp mcp-helper; do
    echo "Running $suite checks"
    "./Tools/run-$suite-checks.sh"
done
