#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for suite in scheduling calendar-persistence calendar-runtime calendar-layout logic editor capture capture-selection duplication reusable-copy inspector-lifetime export export-integration lifecycle application-quit visibility lists-sort today-sorting tasks-view label-merge task-history search reminder reminder-store library-backup sync signing mcp mcp-helper; do
    echo "Running $suite checks"
    "./Tools/run-$suite-checks.sh"
done
