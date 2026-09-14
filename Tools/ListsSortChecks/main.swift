import Foundation
import SwiftData
import SwiftUI
import os

var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

func list(_ title: String, number: Int, position: Double, created: TimeInterval) -> TaskList {
    let value = TaskList(title: title)
    value.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    value.sortIndex = position
    value.createdAt = Date(timeIntervalSince1970: created)
    return value
}

func ids(_ lists: [TaskList], sorting: ListGallerySorting, ascending: Bool = true, archived: Bool = false) -> [UUID] {
    sorting.visibleLists(from: lists, includingArchived: archived, ascending: ascending).map(\.id)
}

let zebra = list("Zebra", number: 1, position: 0, created: 100)
let alpha = list("  alpha  ", number: 2, position: 1, created: 300)
let beta = list("Beta", number: 3, position: 2, created: 200)
let archive = list("Archived", number: 4, position: 3, created: 400)
archive.isArchived = true
let alias = list("Inbox alias", number: 5, position: 4, created: 500)
alias.mergedIntoID = zebra.id
let lists = [beta, alias, alpha, archive, zebra]

check(ids(lists, sorting: .existing) == [zebra.id, alpha.id, beta.id], "existing gallery order follows saved sortIndex")
check(ids(lists, sorting: .existing, ascending: false) == [zebra.id, alpha.id, beta.id], "existing order ignores the previous direction")
check(ids(lists, sorting: .alphabetical) == [alpha.id, beta.id, zebra.id], "alphabetical sorting uses visible trimmed titles, case insensitively")
check(ids(lists, sorting: .alphabetical, ascending: false) == [zebra.id, beta.id, alpha.id], "alphabetical descending reverses title order")
check(ids(lists, sorting: .creationDate) == [zebra.id, beta.id, alpha.id], "creation date sorts oldest first")
check(ids(lists, sorting: .creationDate, ascending: false) == [alpha.id, beta.id, zebra.id], "creation date sorts newest first")
check(ids(lists, sorting: .alphabetical, archived: true) == [alpha.id, archive.id, beta.id, zebra.id], "archived lists take their sorted place when shown; merged aliases remain hidden")
check(ids(lists, sorting: .creationDate, ascending: false, archived: true) == [archive.id, alpha.id, beta.id, zebra.id], "archive visibility composes with descending date sort")
archive.isArchived = false
check(ids(lists, sorting: .existing).contains(archive.id), "unarchiving immediately restores gallery membership")
archive.isArchived = true

let empty = list("", number: 6, position: 6, created: 600)
let whitespace = list(" \n ", number: 7, position: 7, created: 600)
let namedUntitled = list("Untitled list", number: 8, position: 8, created: 600)
let untitled = [namedUntitled, whitespace, zebra, empty]
check(ids(untitled, sorting: .alphabetical) == [empty.id, whitespace.id, namedUntitled.id, zebra.id], "blank and whitespace titles sort as the displayed Untitled list")
check(ids(untitled, sorting: .alphabetical, ascending: false) == [zebra.id, empty.id, whitespace.id, namedUntitled.id], "equal displayed titles keep stable ties in either direction")
check(ids(untitled.reversed(), sorting: .alphabetical) == ids(untitled, sorting: .alphabetical), "ties do not depend on fetch order")

let duplicateEarly = list("Same", number: 10, position: 10, created: 600)
let duplicateLate = list("Same", number: 9, position: 9, created: 700)
check(ids([duplicateLate, duplicateEarly], sorting: .alphabetical) == [duplicateEarly.id, duplicateLate.id], "duplicate titles use creation time before UUID")
let dateTie = [whitespace, namedUntitled, empty]
check(ids(dateTie, sorting: .creationDate) == [empty.id, whitespace.id, namedUntitled.id], "equal creation timestamps use stable UUID ties")
check(ids(dateTie, sorting: .creationDate, ascending: false) == [empty.id, whitespace.id, namedUntitled.id], "date ties remain stable when direction changes")
let positionTieEarly = list("Earlier", number: 12, position: 20, created: 900)
let positionTieLate = list("Later", number: 11, position: 20, created: 1_000)
check(ids([positionTieLate, positionTieEarly], sorting: .existing) == [positionTieEarly.id, positionTieLate.id], "equal manual positions have deterministic existing order")

let renameObserved = OSAllocatedUnfairLock(initialState: false)
withObservationTracking {
    _ = ids(lists, sorting: .alphabetical)
} onChange: {
    renameObserved.withLock { $0 = true }
}
alpha.title = "Zulu"
check(renameObserved.withLock { $0 }, "gallery sorting observes model title edits for immediate SwiftUI refresh")
check(ids(lists, sorting: .alphabetical) == [beta.id, zebra.id, alpha.id], "renaming a list immediately changes its alphabetical position")
let newList = list("Aardvark", number: 13, position: 30, created: 2_000)
check(ids(lists + [newList], sorting: .alphabetical).first == newList.id, "new lists enter the selected alphabetical order")
check(ids(lists + [newList], sorting: .creationDate, ascending: false).first == newList.id, "new lists enter the selected date order")

let sectionID = UUID()
zebra.sectionID = sectionID
zebra.isPinned = true
zebra.sidebarIndex = 42
let updatedAt = zebra.updatedAt
for sorting in ListGallerySorting.allCases {
    for ascending in [true, false] {
        _ = sorting.visibleLists(from: lists, includingArchived: true, ascending: ascending)
    }
}
check(zebra.sortIndex == 0 && alpha.sortIndex == 1 && beta.sortIndex == 2, "sorting never rewrites saved manual positions")
check(zebra.sectionID == sectionID && zebra.isPinned && zebra.sidebarIndex == 42, "gallery sorting leaves sidebar sections, pinning and order untouched")
check(zebra.updatedAt == updatedAt && archive.isArchived, "sorting never touches model timestamps or archived state")

let suite = "solimanali.openlist.lists-sort-checks.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let selection = AppStorage(wrappedValue: ListGallerySorting.existing, ListGallerySorting.preferenceKey, store: defaults)
let ascending = AppStorage(wrappedValue: true, ListGallerySorting.ascendingPreferenceKey, store: defaults)
check(selection.wrappedValue == .existing && ascending.wrappedValue, "fresh installations keep existing order")
selection.wrappedValue = .creationDate
ascending.wrappedValue = false
let reopenedDefaults = UserDefaults(suiteName: suite)!
let reopenedSelection = AppStorage(wrappedValue: ListGallerySorting.existing, ListGallerySorting.preferenceKey, store: reopenedDefaults)
let reopenedAscending = AppStorage(wrappedValue: true, ListGallerySorting.ascendingPreferenceKey, store: reopenedDefaults)
check(reopenedSelection.wrappedValue == .creationDate && !reopenedAscending.wrappedValue, "sort and direction persist when the gallery preference wrapper is recreated")
check(reopenedDefaults.string(forKey: ListGallerySorting.preferenceKey) == "creationDate", "sort choice is stored in local defaults")
defaults.set("future-sort", forKey: ListGallerySorting.preferenceKey)
let unknownSelection = AppStorage(wrappedValue: ListGallerySorting.existing, ListGallerySorting.preferenceKey, store: defaults)
check(unknownSelection.wrappedValue == .existing, "unknown persisted choices safely fall back to existing order")

check(ListGallerySorting.alphabetical.summary(ascending: false) == "Alphabetical · Z to A", "active alphabetical summary includes direction")
check(ListGallerySorting.creationDate.summary(ascending: true) == "Creation date · Oldest first", "active date summary includes direction")
check(ListGallerySorting.existing.summary(ascending: false) == "Existing order", "existing-order summary has no irrelevant direction")

// Sidebar and gallery share a body-local graph for paths and membership.
let owner = TaskList(title: "Owner")
let descendant = TaskList(title: "Child")
descendant.parentListID = owner.id
var nested = [owner, descendant]
var hierarchy = ListHierarchy(nested)
check(hierarchy.path(for: descendant.id) == "Owner › Child", "Shared row projection includes the current owning path")
owner.title = "Renamed owner"
hierarchy = ListHierarchy(nested)
check(hierarchy.path(for: descendant.id) == "Renamed owner › Child", "Rebuilding the parent projection reflects ancestor rename")
owner.isArchived = true
hierarchy = ListHierarchy(nested)
check(ListGallerySorting.existing.visibleLists(from: nested, includingArchived: false, ascending: true, hierarchy: hierarchy).isEmpty
    && hierarchy.isArchived(descendant.id), "Shared gallery membership and card archive state change together")
owner.isArchived = false
descendant.parentListID = UUID()
hierarchy = ListHierarchy(nested)
check(hierarchy.ancestors(of: descendant.id).isEmpty && hierarchy.recoveryContext(for: descendant.id) != nil,
    "Shared projection represents an unavailable parent without a stale breadcrumb")
let arriving = TaskList(title: "Arriving owner"); arriving.id = descendant.parentListID!
nested.append(arriving)
hierarchy = ListHierarchy(nested)
check(hierarchy.path(for: descendant.id) == "Arriving owner › Child" && hierarchy.recoveryContext(for: descendant.id) == nil,
    "Late parent arrival updates shared row paths and clears recovery context")
descendant.parentListID = owner.id
hierarchy = ListHierarchy(nested)
check(hierarchy.path(for: descendant.id) == "Renamed owner › Child",
    "Moving a document updates the shared row projection to its new parent")

print("✅ \(checks) Lists gallery sorting checks passed")
