import Foundation
import Testing
@testable import OpenlistiOS

@MainActor
struct TaskDetailContextTests {
    @Test func parentContextResolvesCompletedAndArchivedParents() throws {
        let phone = try TestPhone(seeded: true)
        let child = try #require(phone.task("Pay the ryokan deposit"))
        let parent = try #require(phone.task("Book the ryokan"))
        let list = try #require(phone.list("Weekend in Kyoto"))
        #expect(TaskDetailContext.parent(of: child, in: phone.store)?.id == parent.id)
        #expect(TaskDetailContext.parent(of: parent, in: phone.store) == nil)
        parent.isCompleted = true
        phone.store.setArchived(true, for: list)
        #expect(TaskDetailContext.parent(of: child, in: phone.store)?.id == parent.id)
    }

    @Test func invalidParentReferencesNeverCreateANavigationTarget() throws {
        let phone = try TestPhone(seeded: true)
        let child = try #require(phone.task("Pay the ryokan deposit"))
        let parent = try #require(phone.task("Book the ryokan"))
        child.parentID = UUID()
        #expect(TaskDetailContext.parent(of: child, in: phone.store) == nil)
        child.parentID = child.id
        #expect(TaskDetailContext.parent(of: child, in: phone.store) == nil)
        child.parentID = parent.id
        parent.parentID = child.id
        #expect(TaskDetailContext.parent(of: child, in: phone.store) == nil)
        parent.parentID = nil
        parent.kindRaw = BlockKind.paragraph.rawValue
        #expect(TaskDetailContext.parent(of: child, in: phone.store) == nil)
        parent.kindRaw = BlockKind.task.rawValue
        parent.trashID = UUID()
        #expect(TaskDetailContext.parent(of: child, in: phone.store) == nil)
        phone.navigator.show(.taskDetail(child.id), in: child.listID)
        let original = phone.navigator.listsPath
        TaskDetailContext.openParent(of: child, in: phone.env)
        #expect(phone.navigator.listsPath == original)
    }

    @Test func parentNavigationReusesTheStackWithoutParentChildCycles() throws {
        let phone = try TestPhone(seeded: true)
        let child = try #require(phone.task("Pay the ryokan deposit"))
        let parent = try #require(phone.task("Book the ryokan"))
        let listID = try #require(child.listID)
        phone.navigator.show(.taskDetail(child.id), in: listID)
        TaskDetailContext.openParent(of: child, in: phone.env)
        #expect(phone.navigator.listsPath == [.list(listID), .taskDetail(parent.id)])
        phone.navigator.open(.taskDetail(child.id))
        TaskDetailContext.openParent(of: child, in: phone.env)
        #expect(phone.navigator.listsPath == [.list(listID), .taskDetail(parent.id)])
        phone.navigator.pop()
        #expect(phone.navigator.visibleRoute == .list(listID))

        phone.navigator.open(.settings)
        phone.navigator.settingsPath = [.activity, .taskDetail(parent.id), .taskDetail(child.id)]
        TaskDetailContext.openParent(of: child, in: phone.env)
        #expect(phone.navigator.settingsPath == [.activity, .taskDetail(parent.id)])
    }

    @Test func planningCannotEnableArchivedTasksButCanClearExistingSelection() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        let reading = try #require(phone.list("Reading"))
        let home = try #require(phone.list("Home"))
        #expect(phone.store.moveList(reading, under: home.id))
        phone.store.setArchived(true, for: home)
        TaskDetailContext.setPlanned(true, for: task, in: phone.env)
        #expect(task.selectedForDay == nil)
        #expect(phone.env.tray.message == nil)

        phone.store.setArchived(false, for: home)
        TaskDetailContext.setPlanned(true, for: task, in: phone.env)
        let selected = try #require(task.selectedForDay)
        phone.store.setArchived(true, for: home)
        TaskDetailContext.setPlanned(false, for: task, in: phone.env)
        #expect(task.selectedForDay == nil)
        #expect(task.dueDate == nil)
        phone.env.tray.performAction()
        #expect(task.selectedForDay == selected, "Clearing an archived selection remains undoable")
    }
}
