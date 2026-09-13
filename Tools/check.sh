#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for suite in scheduling calendar-persistence calendar-runtime calendar-layout logic editor capture capture-selection duplication export export-integration lifecycle visibility lists-sort today-sorting sync signing mcp mcp-helper; do
    echo "Running $suite checks"
    "./Tools/run-$suite-checks.sh"
done
