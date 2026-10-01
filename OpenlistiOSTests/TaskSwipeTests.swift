import Foundation
import Testing
@testable import OpenlistiOS

@MainActor
struct TaskSwipeTests {
    @Test func shortSwipesRevealControlsWithoutCommitting() {
        #expect(TaskSwipeMotion.result(translation: 37, width: 350) == .closed)
        #expect(TaskSwipeMotion.result(translation: 38, width: 350) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: 94, width: 350) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: -94, width: 350) == .delete)
        #expect(TaskSwipeMotion.result(translation: -37, width: 350) == .closed)
    }

    @Test func fullSwipeRequiresPhysicalTravelEvenWhenControlsAreOpen() {
        let threshold = TaskSwipeMotion.todayDistance(width: 350)
        #expect(TaskSwipeMotion.result(translation: threshold - 1, width: 350) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: threshold, width: 350) == .today)
        #expect(TaskSwipeMotion.result(translation: 100, origin: TaskSwipeMotion.shortcutsWidth, width: 350) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: -74, origin: TaskSwipeMotion.shortcutsWidth, width: 350) == .closed)
        #expect(TaskSwipeMotion.result(translation: -TaskSwipeMotion.trashDistance(width: 350), width: 350) == .trash)
        #expect(TaskSwipeMotion.result(translation: threshold, width: 350, allowsToday: false) == .shortcuts)
    }

    @Test func verticalAndDiagonalDragsRemainScrollGestures() {
        #expect(!TaskSwipeMotion.isHorizontal(x: 0, y: 100))
        #expect(!TaskSwipeMotion.isHorizontal(x: 100, y: 100))
        #expect(!TaskSwipeMotion.isHorizontal(x: -30, y: 100))
        #expect(TaskSwipeMotion.isHorizontal(x: 100, y: 20))
        #expect(TaskSwipeMotion.isHorizontal(x: -100, y: 20))
    }

    @Test func actionChoicesPersistAndDuplicateChoicesSwapPositions() {
        let defaults = TestDefaults.make()
        let preferences = TaskSwipePreferences(defaults: defaults)
        #expect(preferences.first == .moveToList)
        #expect(preferences.second == .star)
        preferences.set(.tomorrow, for: .first)
        preferences.set(.complete, for: .second)
        let reloaded = TaskSwipePreferences(defaults: defaults)
        #expect(reloaded.first == .tomorrow)
        #expect(reloaded.second == .complete)
        reloaded.set(.complete, for: .first)
        #expect(reloaded.first == .complete)
        #expect(reloaded.second == .tomorrow)
        #expect(TaskSwipePreferences(defaults: defaults).second == .tomorrow)
    }

    @Test func unknownAndDuplicateSavedChoicesHaveUsableDefaults() {
        let defaults = TestDefaults.make()
        defaults.set("removed-action", forKey: "phone.swipe.first")
        defaults.set("moveToList", forKey: "phone.swipe.second")
        let preferences = TaskSwipePreferences(defaults: defaults)
        #expect(preferences.first == .moveToList)
        #expect(preferences.second == .star)
    }

    @Test func addingToTodayKeepsDueDateAndUndoRestoresMembership() throws {
        for offset in [-3, 0, 4] {
            let phone = try TestPhone(seeded: true)
            let task = try #require(phone.task("Start Piranesi"))
            let due = try #require(TestClock.calendar.date(byAdding: .day, value: offset, to: TestClock.mockupNow))
            phone.env.actions.schedule([task], on: due, includesTime: true)
            #expect(task.selectedForDay == nil)
            phone.env.actions.addToToday(task)
            #expect(task.isPlanned(on: TestClock.mockupNow, calendar: TestClock.calendar))
            #expect(task.dueDate == due)
            #expect(task.includesTime)
            #expect(phone.env.tray.message?.actionTitle == "Undo")
            phone.env.tray.performAction()
            #expect(task.selectedForDay == nil)
            #expect(task.dueDate == due)
            #expect(task.includesTime)
        }
    }

    @Test func repeatedLongRightNeverRemovesTodayOrCompletesTask() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.addToToday(task)
        let selected = task.selectedForDay
        phone.env.actions.addToToday(task)
        #expect(task.selectedForDay == selected)
        #expect(!task.isCompleted)
        #expect(task.dueDate == nil)
        #expect(phone.env.tray.message?.actionTitle == "Undo")
        phone.env.tray.performAction()
        #expect(task.selectedForDay == nil)
    }

    @Test func completedAndClosingTasksCannotBeAddedByFullSwipe() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.toggle(task)
        phone.env.actions.addToToday(task)
        #expect(task.selectedForDay == nil)
        phone.env.actions.settle(task.id)
        phone.env.actions.addToToday(task)
        #expect(task.isCompleted)
        #expect(task.selectedForDay == nil)
    }

    @Test func archivedAncestorsPreventTodayUntilTheSourceIsActiveAgain() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        let reading = try #require(phone.list("Reading"))
        let parent = try #require(phone.list("Home"))
        #expect(phone.store.moveList(reading, under: parent.id))
        let activeSnapshot = phone.store.listHierarchy()
        #expect(phone.env.actions.canAddToToday(task, hierarchy: activeSnapshot))

        phone.store.setArchived(true, for: parent)
        #expect(!reading.isArchived, "The inherited archive must be checked, not just the child's flag")
        #expect(!phone.env.actions.canAddToToday(task))
        #expect(!phone.env.actions.canAddToToday(task, hierarchy: phone.store.listHierarchy()))
        phone.env.actions.addToToday(task)
        #expect(task.selectedForDay == nil)
        #expect(task.dueDate == nil)
        #expect(phone.env.tray.message == nil, "An archived task must not report that it was added to Today")

        // A stale gesture snapshot may still allow the drag, but the action
        // above must recheck the live source rather than trusting that snapshot.
        #expect(phone.env.actions.canAddToToday(task, hierarchy: activeSnapshot))
        phone.store.setArchived(false, for: parent)
        #expect(phone.env.actions.canAddToToday(task))
        phone.env.actions.addToToday(task)
        #expect(task.isPlanned(on: TestClock.mockupNow, calendar: TestClock.calendar))
        phone.env.tray.performAction()
        #expect(task.selectedForDay == nil)
    }
}
