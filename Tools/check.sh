#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for suite in scheduling calendar-persistence calendar-runtime calendar-layout logic editor capture capture-selection block-selection duplication reusable-copy fragment inspector-lifetime export export-integration lifecycle application-quit visibility lists-sort today-sorting tasks-view list-tasks label-merge task-history search reminder reminder-store inbox inbox-navigation library-backup trash sync signing mcp mcp-helper; do
    echo "Running $suite checks"
    "./Tools/run-$suite-checks.sh"
done
