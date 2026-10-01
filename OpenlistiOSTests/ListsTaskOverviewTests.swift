import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

@MainActor
struct ListsTaskOverviewTests {
    @Test func allListsIncludesInboxAndTasksFromEveryActiveList() throws {
        let phone = try TestPhone(seeded: true)
        let (library, blocks) = try snapshot(phone)
        let tasks = ListsTaskOverview.tasks(in: library, blocks: blocks)
        #expect(tasks.count == 25)
        #expect(Set(tasks.compactMap(\.listID)) == Set(library.lists.map(\.id)))
        #expect(tasks.allSatisfy { !$0.isCompleted && $0.trashID == nil })
        #expect(Set(tasks.map(\.id)).count == tasks.count)
    }

    @Test func aCombinationOfListsFiltersTheQueueWithoutChangingTaskOwnership() throws {
        let phone = try TestPhone(seeded: true)
        let home = try #require(phone.list("Home"))
        let reading = try #require(phone.list("Reading"))
        let (library, blocks) = try snapshot(phone)
        let tasks = ListsTaskOverview.tasks(in: library, blocks: blocks, selectedLists: [home.id, reading.id])
        #expect(tasks.count == 5)
        #expect(Set(tasks.compactMap(\.listID)) == [home.id, reading.id])
        #expect(tasks.contains { $0.displayTitle == "Fix the dripping bathroom tap" })
        #expect(tasks.contains { $0.displayTitle == "Start Piranesi" })
    }

    @Test func dueDatesLeadAndTiesKeepDocumentOrder() {
        let firstList = TaskList(title: "First")
        let secondList = TaskList(title: "Second")
        secondList.sortIndex = 1
        secondList.sidebarIndex = 1
        let earlier = Block(kind: .task, text: "Earlier", listID: secondList.id)
        earlier.dueDate = TestClock.mockupNow.addingTimeInterval(-86_400)
        let firstDue = Block(kind: .task, text: "First due", listID: firstList.id, sortIndex: 2)
        firstDue.dueDate = TestClock.mockupNow
        let secondDue = Block(kind: .task, text: "Second due", listID: secondList.id, sortIndex: 1)
        secondDue.dueDate = TestClock.mockupNow
        let firstUndated = Block(kind: .task, text: "First undated", listID: firstList.id, sortIndex: 1)
        let secondUndated = Block(kind: .task, text: "Second undated", listID: firstList.id, sortIndex: 3)
        let blocks = [secondUndated, secondDue, firstDue, earlier, firstUndated]
        let library = NextLibrary(lists: [secondList, firstList], sections: [], labels: [], tasks: blocks)
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks).map(\.displayTitle)
            == ["Earlier", "First due", "Second due", "First undated", "Second undated"])
    }

    @Test func archivedAncestorsAndTrashStayOutWhileNestedSourcesStayVisible() {
        let root = TaskList(title: "Projects")
        let child = TaskList(title: "Reading")
        child.parentListID = root.id
        let active = Block(kind: .task, text: "Nested", listID: child.id)
        let trashed = Block(kind: .task, text: "Trashed", listID: child.id)
        trashed.trashID = UUID()
        let completed = Block(kind: .task, text: "Completed", listID: root.id)
        completed.isCompleted = true
        let blocks = [active, trashed, completed]
        var library = NextLibrary(lists: [root, child], sections: [], labels: [], tasks: blocks)
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks).map(\.id) == [active.id])
        #expect(ListsTaskOverview.source(of: active, in: library) == "Projects › Reading")
        root.isArchived = true
        library = NextLibrary(lists: [root, child], sections: [], labels: [], tasks: blocks)
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks).isEmpty)
    }

    @Test func losingASelectedListFallsBackToAllRemainingLists() throws {
        let phone = try TestPhone(seeded: true)
        let home = try #require(phone.list("Home"))
        let reading = try #require(phone.list("Reading"))
        phone.store.setArchived(true, for: home)
        let (library, blocks) = try snapshot(phone)
        let all = ListsTaskOverview.tasks(in: library, blocks: blocks)
        #expect(!all.contains { $0.listID == home.id })
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks, selectedLists: [home.id]).map(\.id) == all.map(\.id))
        let survivingSelection = ListsTaskOverview.tasks(in: library, blocks: blocks, selectedLists: [home.id, reading.id])
        #expect(survivingSelection.count == 2)
        #expect(survivingSelection.allSatisfy { $0.listID == reading.id })
    }

    @Test func sharedTaskActionsUpdateTheOverviewAndUndoRestoresIt() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        let reading = try #require(phone.list("Reading"))
        let home = try #require(phone.list("Home"))
        #expect(phone.env.actions.move([task], to: home))
        var (library, blocks) = try snapshot(phone)
        #expect(ListsTaskOverview.source(of: task, in: library) == "Home")
        #expect(!ListsTaskOverview.tasks(in: library, blocks: blocks, selectedLists: [reading.id]).contains { $0.id == task.id })
        phone.env.tray.performAction()
        (library, blocks) = try snapshot(phone)
        #expect(ListsTaskOverview.source(of: task, in: library) == "Reading")

        phone.env.actions.complete([task])
        (library, blocks) = try snapshot(phone)
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks).contains { $0.id == task.id }, "Completion stays during Undo dwell")
        phone.env.actions.settle(task.id)
        (library, blocks) = try snapshot(phone)
        #expect(!ListsTaskOverview.tasks(in: library, blocks: blocks).contains { $0.id == task.id })
        phone.env.tray.performAction()
        (library, blocks) = try snapshot(phone)
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks).contains { $0.id == task.id })

        #expect(phone.env.actions.trash([task]))
        (library, blocks) = try snapshot(phone)
        #expect(!ListsTaskOverview.tasks(in: library, blocks: blocks).contains { $0.id == task.id })
        phone.env.tray.performAction()
        (library, blocks) = try snapshot(phone)
        #expect(ListsTaskOverview.tasks(in: library, blocks: blocks).contains { $0.id == task.id })
    }

    private func snapshot(_ phone: TestPhone) throws -> (NextLibrary, [Block]) {
        let blocks = try phone.container.mainContext.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil }))
        let library = NextLibrary(lists: phone.store.allLists(includeArchived: true), sections: phone.store.allSections(),
                                  labels: phone.store.allLabels(), tasks: blocks.filter(\.isTask))
        return (library, blocks)
    }
}
