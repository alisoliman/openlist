#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for suite in scheduling calendar-persistence calendar-runtime calendar-layout logic editor capture block-selection drag-payload bulk-action duplication reusable-copy fragment inspector-lifetime inspector-text export export-integration lifecycle application-quit visibility list-tasks label-merge task-history activity-heatmap search local-links widget reminder reminder-store inbox inbox-navigation library-backup trash list-cover nested-list sync widget-snapshot widget-action signing mcp mcp-helper; do
    echo "Running $suite checks"
    "./Tools/run-$suite-checks.sh"
done
