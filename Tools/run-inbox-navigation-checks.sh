#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/inbox-navigation-checks" \
    openlist/Model/Block.swift openlist/Model/InboxMembership.swift openlist/Model/BlockKind.swift \
    openlist/Model/Recurrence.swift openlist/Model/CalendarTypes.swift openlist/Model/TaskList.swift \
    openlist/Model/SidebarSection.swift openlist/Model/SearchOptions.swift openlist/Model/SearchHit.swift \
    openlist/Model/ContentReveal.swift Shared/ListAccent.swift \
    openlist/Services/BlockTree.swift openlist/Model/ListViewMode.swift openlist/Services/Navigator.swift \
    Tools/InboxNavigationChecks/main.swift
"$OUT/inbox-navigation-checks"
