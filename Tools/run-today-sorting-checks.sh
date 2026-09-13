#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/today-sorting-checks" \
    openlist/Model/Block.swift openlist/Model/TrashMetadata.swift openlist/Model/InboxMembership.swift openlist/Model/BlockKind.swift openlist/Model/Recurrence.swift \
    openlist/Model/CalendarTypes.swift openlist/Model/TaskList.swift openlist/Model/SidebarSection.swift \
    openlist/Model/TodaySorting.swift Shared/ListAccent.swift openlist/Services/BlockTree.swift \
    openlist/Services/ActiveTaskPolicy.swift openlist/Services/TodayTaskBuckets.swift \
    Tools/TodaySortingChecks/main.swift

"$OUT/today-sorting-checks"
PREFERENCE_SUITE="openlist.today-sorting-checks.$(uuidgen)"
"$OUT/today-sorting-checks" write "$PREFERENCE_SUITE"
"$OUT/today-sorting-checks" relaunch "$PREFERENCE_SUITE"
"$OUT/today-sorting-checks" reset "$PREFERENCE_SUITE"
