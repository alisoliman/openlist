import AppKit
import Foundation

// The window's own navigation and focus, through the app's Workbench: the
// focus moving on to the row beside one that leaves, Back from a task
// opened out as a page, and Delete everything leaving no page it took away
// in the history. Last, as Delete everything empties the library.

@MainActor
func runWindowWorkbenchChecks() {
    _ = NSApplication.shared
    let navigator = workbench.navigator

    // A row leaving hands the focus to the one beside it.
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    check(Workbench.neighbour(of: b, leaving: [b], in: [a, b, c, d]) == c, "the row after one leaving takes the focus")
    check(Workbench.neighbour(of: b, leaving: [b, c], in: [a, b, c, d]) == d, "past the rows leaving with it")
    check(Workbench.neighbour(of: d, leaving: [d], in: [a, b, c, d]) == c, "with none after it, the row before it")
    check(Workbench.neighbour(of: b, leaving: [a, b, c, d], in: [a, b, c, d]) == nil, "with every row gone, none")
    check(Workbench.neighbour(of: UUID(), leaving: [], in: [a, b]) == nil, "a row not on show has none")

    // D on the focused row moves the focus on, so J goes on from there, not the top.
    let flights = task("Book the flights"), bags = task("Pack the bags"), plants = task("Water the plants")
    workbench.visibleIDs = [flights.id, bags.id, plants.id]
    workbench.focusID = bags.id
    workbench.trash([bags.id])
    check(workbench.focusID == plants.id, "trashing the focused row focuses the row after it")
    workbench.flushClosings()
    workbench.visibleIDs = [flights.id, plants.id]
    workbench.trash([plants.id])
    check(workbench.focusID == flights.id, "and the last row's, the row before it")
    workbench.flushClosings()
    check(bags.trashID != nil && plants.trashID != nil, "fixture: the rows land in Trash")

    // Back from a task opened out as a page puts it back beside its screen
    // first, as the crumb reads, then goes back through the history.
    workbench.go(.today)
    workbench.go(.calendar)
    navigator.openTask(flights.id)
    workbench.toggleTaskPage()
    check(workbench.isTaskPageOpen && workbench.canGoBack && workbench.backRoute == .calendar,
          "with a task opened out, Back goes to the screen under it")
    workbench.goBack()
    check(!workbench.isTaskPageOpen && navigator.route == .calendar && navigator.openTaskID == flights.id,
          "Back puts the page back beside its screen, the details still open")
    check(workbench.backRoute == .today, "then Back names the page before")
    workbench.goBack()
    check(navigator.route == .today && navigator.openTaskID == flights.id, "and goes there, the details with it")
    navigator.pruneHistory { _ in false }
    workbench.toggleTaskPage()
    check(workbench.canGoBack && !navigator.canGoBack, "with no history, Back still puts the page back")
    workbench.goBack()
    check(!workbench.isTaskPageOpen && !workbench.canGoBack && navigator.route == .today, "and then has nowhere to go")

    // Delete everything takes the pages it took away out of the history,
    // and the task out of the details.
    workbench.go(.list(home.id))
    workbench.go(.today)
    workbench.go(.settings)
    check(workbench.resetLibrary(), "fixture: Delete everything finishes")
    check(navigator.openTaskID == nil && navigator.backRoute == .today, "Delete everything leaves no page it deleted behind Back")
    navigator.goBack()
    check(navigator.route == .today && !navigator.canGoBack, "and the visits either side of one it took join")
}
