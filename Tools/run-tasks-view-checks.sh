#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/tasks-view-checks" \
    openlist/Model/Block.swift openlist/Model/InboxMembership.swift openlist/Model/BlockKind.swift openlist/Model/Recurrence.swift \
    openlist/Model/CalendarTypes.swift openlist/Model/TaskList.swift openlist/Model/TaskLabel.swift \
    openlist/Model/TaskFilter.swift openlist/Model/TaskGrouping.swift openlist/Model/TaskSorting.swift \
    openlist/Model/TasksViewOptions.swift Shared/ListAccent.swift openlist/Services/ActiveTaskPolicy.swift \
    openlist/Services/TasksGroup.swift openlist/Services/TasksProjection.swift \
    openlist/Design/Theme.swift openlist/Views/TaskSortMenu.swift \
    openlist/Views/TaskTitleFilter.swift openlist/Views/TasksViewControls.swift \
    Tools/TasksViewChecks/main.swift

"$OUT/tasks-view-checks"
