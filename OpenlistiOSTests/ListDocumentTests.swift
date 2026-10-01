import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

@MainActor
struct ListDocumentTests {
    @Test func aParagraphOnlyDocumentIsNotAnEmptyList() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Notes")
        let note = Block(kind: .paragraph, text: "Keep the train confirmation here.", listID: list.id)
        try persist([note], in: library)

        let document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)

        #expect(document.page.rows.map(\.id) == [note.id])
        #expect(document.page.openCount == 0)
        #expect(document.page.completed.isEmpty)
        #expect(document.selectableTasks.isEmpty)
        #expect(!document.canDisclose(try #require(document.page.rows.first)))
    }

    @Test func aHeadingCollapsesOnlyItsSectionAndReopensStoredContent() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Travel")
        let heading = Block(kind: .heading1, text: "Before leaving", listID: list.id, sortIndex: 0)
        let task = Block(kind: .task, text: "Book the train", listID: list.id, sortIndex: 1)
        let subheading = Block(kind: .heading2, text: "Documents", listID: list.id, sortIndex: 2)
        let note = Block(kind: .paragraph, text: "Bring both passports.", listID: list.id, sortIndex: 3)
        let nextHeading = Block(kind: .heading1, text: "On arrival", listID: list.id, sortIndex: 4)
        let nextNote = Block(kind: .paragraph, text: "The key is at reception.", listID: list.id, sortIndex: 5)
        let blocks = [heading, task, subheading, note, nextHeading, nextNote]
        try persist(blocks, in: library)

        var document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        #expect(document.page.rows.map(\.id) == blocks.map(\.id))
        let headingRow = try #require(document.page.rows.first)
        #expect(!headingRow.hasChildren, "A heading section uses document order, not parent IDs")
        #expect(document.canDisclose(headingRow))

        library.store.toggleCollapse(heading)
        document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        #expect(heading.isCollapsed)
        #expect(document.page.rows.map(\.id) == [heading.id, nextHeading.id, nextNote.id])
        #expect(document.canDisclose(try #require(document.page.rows.first)))
        #expect(document.page.openCount == 1, "Folding a section does not complete its task")
        #expect(document.selectableTasks.isEmpty)

        library.store.toggleCollapse(heading)
        document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        #expect(!heading.isCollapsed)
        #expect(document.page.rows.map(\.id) == blocks.map(\.id))
        #expect(document.selectableTasks.map(\.id) == [task.id])
    }

    @Test func aStoredTaskFoldReopensAndProgressCountsOnlyImmediateTaskChildren() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Project")
        let parent = Block(kind: .task, text: "Prepare the release", listID: list.id)
        parent.isCollapsed = true
        let open = Block(kind: .task, text: "Review the copy", listID: list.id, parentID: parent.id, sortIndex: 0)
        let done = Block(kind: .task, text: "Prepare screenshots", listID: list.id, parentID: parent.id, sortIndex: 1)
        done.isCompleted = true
        let note = Block(kind: .paragraph, text: "Use the approved wording.", listID: list.id, parentID: parent.id, sortIndex: 2)
        let grandchild = Block(kind: .task, text: "Proofread", listID: list.id, parentID: open.id)
        grandchild.isCompleted = true
        try persist([parent, open, done, note, grandchild], in: library)

        var document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        #expect(document.page.rows.map(\.id) == [parent.id])
        #expect(document.canDisclose(try #require(document.page.rows.first)))
        let foldedProgress = try #require(document.progress(for: parent))
        #expect(foldedProgress.done == 1 && foldedProgress.total == 2)

        library.store.toggleCollapse(parent)
        document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        #expect(!parent.isCollapsed)
        #expect(document.page.rows.map(\.id) == [parent.id, open.id, grandchild.id, done.id, note.id])
        #expect(document.page.rows.first { $0.id == open.id }?.depth == 1)
        #expect(document.page.rows.first { $0.id == grandchild.id }?.depth == 2)
        #expect(document.page.completed.isEmpty, "Completed subtasks stay in their branch")
        #expect(document.progress(for: done)?.total == nil)

        let closing = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual, closing: [open.id])
        let closingProgress = try #require(closing.progress(for: parent))
        #expect(closingProgress.done == 2 && closingProgress.total == 2)
        #expect(!open.isCompleted, "Undo dwell counts as progress without changing the saved task yet")
    }

    @Test func selectionContainsOnlyVisibleOpenTasksOutsideTheClosingDwell() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Selection")
        let heading = Block(kind: .heading1, text: "This week", listID: list.id, sortIndex: 0)
        let note = Block(kind: .paragraph, text: "Discuss in person.", listID: list.id, sortIndex: 1)
        let open = Block(kind: .task, text: "Send the agenda", listID: list.id, sortIndex: 2)
        let done = Block(kind: .task, text: "Reserve the room", listID: list.id, sortIndex: 3)
        done.isCompleted = true
        let closing = Block(kind: .task, text: "Invite the team", listID: list.id, sortIndex: 4)
        let parent = Block(kind: .task, text: "Prepare material", listID: list.id, sortIndex: 5)
        parent.isCollapsed = true
        let hidden = Block(kind: .task, text: "Draft slides", listID: list.id, parentID: parent.id)
        try persist([heading, note, open, done, closing, parent, hidden], in: library)

        let document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual, closing: [closing.id])

        #expect(document.selectableTasks.map(\.id) == [open.id, parent.id])
        #expect(document.page.rows.contains { $0.id == closing.id }, "The closing row remains visible during Undo dwell")
        #expect(document.page.completed.map(\.id) == [done.id])
    }

    @Test func theDoneFoldKeepsCompletionOrderAndDoesNotDuplicateVisibleBranches() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Done")
        let heading = Block(kind: .heading1, text: "Work", listID: list.id, sortIndex: 0)
        let older = Block(kind: .task, text: "Earlier completion", listID: list.id, sortIndex: 1)
        older.isCompleted = true
        older.completedAt = TestClock.mockupNow.addingTimeInterval(-60)
        let newer = Block(kind: .task, text: "Later completion", listID: list.id, sortIndex: 2)
        newer.isCompleted = true
        newer.completedAt = TestClock.mockupNow
        let parent = Block(kind: .task, text: "Open parent", listID: list.id, sortIndex: 3)
        let doneChild = Block(kind: .task, text: "Done child", listID: list.id, parentID: parent.id)
        doneChild.isCompleted = true
        let doneParent = Block(kind: .task, text: "Done parent with unfinished work", listID: list.id, sortIndex: 4)
        doneParent.isCompleted = true
        let openChild = Block(kind: .task, text: "Unfinished child", listID: list.id, parentID: doneParent.id)
        let closing = Block(kind: .task, text: "Still closing", listID: list.id, sortIndex: 5)
        closing.isCompleted = true
        try persist([heading, older, newer, parent, doneChild, doneParent, openChild, closing], in: library)

        let document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual, closing: [closing.id])

        #expect(document.page.completed.map(\.id) == [newer.id, older.id])
        let visibleIDs: [UUID] = [heading.id, parent.id, doneChild.id, doneParent.id, openChild.id, closing.id]
        #expect(document.page.rows.map(\.id) == visibleIDs)
        #expect(document.page.openCount == 3)
        #expect(document.selectableTasks.map(\.id) == [parent.id, openChild.id])
        #expect(Set(document.page.rows.map(\.id)).isDisjoint(with: document.page.completed.map(\.id)))
    }

    @Test func sortingKeepsHeadingsAndProseBetweenTheirTaskRuns() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Document order")
        let intro = Block(kind: .paragraph, text: "Introduction", listID: list.id, sortIndex: 0)
        let zulu = Block(kind: .task, text: "Zulu", listID: list.id, sortIndex: 1)
        let childNote = Block(kind: .paragraph, text: "Zulu note", listID: list.id, parentID: zulu.id)
        let alpha = Block(kind: .task, text: "Alpha", listID: list.id, sortIndex: 2)
        let heading = Block(kind: .heading2, text: "Another section", listID: list.id, sortIndex: 3)
        let delta = Block(kind: .task, text: "Delta", listID: list.id, sortIndex: 4)
        let charlie = Block(kind: .task, text: "Charlie", listID: list.id, sortIndex: 5)
        let outro = Block(kind: .paragraph, text: "Closing note", listID: list.id, sortIndex: 6)
        try persist([intro, zulu, childNote, alpha, heading, delta, charlie, outro], in: library)

        let document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .alphabetical)

        let sortedIDs: [UUID] = [intro.id, alpha.id, zulu.id, childNote.id, heading.id, charlie.id, delta.id, outro.id]
        #expect(document.page.rows.map(\.id) == sortedIDs)
        #expect(document.selectableTasks.map(\.id) == [alpha.id, zulu.id, charlie.id, delta.id])
    }

    @Test func completedProjectedRootsRemainReachableWithoutRepairingSavedParentIDs() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Incomplete ancestry")
        let missingParentID = UUID()
        let missing = Block(kind: .task, text: "Missing parent", listID: list.id, parentID: missingParentID)
        let trashedParent = Block(kind: .paragraph, text: "Trashed parent", listID: list.id)
        trashedParent.trashID = UUID()
        let trashed = Block(kind: .task, text: "Trashed parent child", listID: list.id, parentID: trashedParent.id)
        let deletedParent = Block(kind: .paragraph, text: "Deleted parent", listID: list.id)
        let deleted = Block(kind: .task, text: "Deleted parent child", listID: list.id, parentID: deletedParent.id)
        let cycleRoot = Block(kind: .task, text: "Projected cycle root", listID: list.id)
        cycleRoot.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let cycleChild = Block(kind: .task, text: "Projected cycle child", listID: list.id, parentID: cycleRoot.id)
        cycleChild.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        cycleRoot.parentID = cycleChild.id
        let tasks = [missing, trashed, deleted, cycleRoot, cycleChild]
        for (index, task) in tasks.enumerated() {
            task.isCompleted = true
            task.completedAt = TestClock.mockupNow.addingTimeInterval(TimeInterval(-60 * index))
        }
        try persist(tasks + [trashedParent, deletedParent], in: library)
        library.container.mainContext.delete(deletedParent)
        try library.container.mainContext.save()
        let savedParents = tasks.map(\.parentID)
        let blocks = try library.container.mainContext.fetch(FetchDescriptor<Block>())

        let document = ListDocument(blocks: blocks, sorting: .manual)

        #expect(document.page.rows.isEmpty)
        #expect(document.page.completed.map(\.id) == [missing.id, trashed.id, deleted.id, cycleRoot.id])
        #expect(document.page.openCount == 0)
        #expect(document.selectableTasks.isEmpty)
        #expect(tasks.map(\.parentID) == savedParents, "Projection must not rewrite missing or cyclic ancestry")
        #expect(!library.container.mainContext.hasChanges)
    }

    @Test func aNestedHeadingKeepsItsDepthWithoutFoldingTopLevelContent() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Nested headings")
        let parent = Block(kind: .paragraph, text: "Document context", listID: list.id, sortIndex: 0)
        let nested = Block(kind: .heading1, text: "Nested heading", listID: list.id, parentID: parent.id)
        nested.isCollapsed = true
        let nestedNote = Block(kind: .paragraph, text: "Nested body", listID: list.id, parentID: nested.id)
        let outside = Block(kind: .task, text: "Independent task", listID: list.id, sortIndex: 1)
        let heading = Block(kind: .heading1, text: "Following section", listID: list.id, sortIndex: 2)
        let note = Block(kind: .paragraph, text: "Following body", listID: list.id, sortIndex: 3)
        try persist([parent, nested, nestedNote, outside, heading, note], in: library)

        var document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        let visibleIDs: [UUID] = [parent.id, nested.id, nestedNote.id, outside.id, heading.id, note.id]
        #expect(document.page.rows.map(\.id) == visibleIDs)
        let nestedRow = try #require(document.page.rows.first { $0.id == nested.id })
        #expect(nestedRow.depth == 1)
        #expect(!document.canDisclose(nestedRow))
        #expect(nested.isCollapsed, "A read-only projection keeps the stored fold unchanged")
        let topLevelRow = try #require(document.page.rows.first { $0.id == heading.id })
        #expect(topLevelRow.depth == 0)
        #expect(document.canDisclose(topLevelRow))

        library.store.toggleCollapse(heading)
        document = ListDocument(blocks: library.store.blocks(inList: list.id), sorting: .manual)
        #expect(document.page.rows.map(\.id) == [parent.id, nested.id, nestedNote.id, outside.id, heading.id])
        #expect(document.selectableTasks.map(\.id) == [outside.id])
    }

    private func persist(_ blocks: [Block], in library: TestLibrary) throws {
        for block in blocks { library.container.mainContext.insert(block) }
        try library.container.mainContext.save()
    }
}
