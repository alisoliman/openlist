#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -O -swift-version 6 -default-isolation MainActor -o "$OUT/search-checks" \
    openlist/Model/Block.swift openlist/Model/InboxMembership.swift openlist/Model/BlockKind.swift openlist/Model/Recurrence.swift \
    openlist/Model/CalendarTypes.swift openlist/Model/TaskList.swift openlist/Model/SidebarSection.swift \
    openlist/Model/SearchOptions.swift openlist/Model/SearchHit.swift openlist/Model/SearchCorpus.swift \
    openlist/Model/SearchResultSelection.swift openlist/Model/ContentReveal.swift Shared/ListAccent.swift \
    openlist/Services/SearchProjection.swift openlist/Services/SearchSession.swift \
    openlist/Services/BlockTree.swift openlist/Model/ListViewMode.swift openlist/Services/Navigator.swift \
    Tools/SearchChecks/main.swift
"$OUT/search-checks"
