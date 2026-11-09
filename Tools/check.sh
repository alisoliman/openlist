#!/bin/bash
# Runs every check suite, or only those named: ./Tools/check.sh ios-core voice
set -euo pipefail
cd "$(dirname "$0")/.."
SUITES=(scheduling calendar-persistence calendar-runtime calendar-layout logic editor rich-text-parity capture shared-logic voice block-selection drag-payload bulk-action duplication reusable-copy fragment inspector-lifetime inspector-text export export-integration lifecycle application-quit visibility list-tasks label-merge task-history activity-heatmap search local-links widget reminder reminder-store inbox inbox-navigation library-backup trash list-cover nested-list sync widget-snapshot widget-action widget-workbench ios-core signing mcp mcp-helper)
if [[ $# -gt 0 ]]; then
    for suite in "$@"; do
        [[ -x "./Tools/run-$suite-checks.sh" ]] || { echo "No check suite named $suite" >&2; exit 1; }
    done
    SUITES=("$@")
fi
for suite in "${SUITES[@]}"; do
    echo "Running $suite checks"
    "./Tools/run-$suite-checks.sh"
done
