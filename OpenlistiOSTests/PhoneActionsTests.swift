//
//  PhoneActionsTests.swift
//  OpenlistiOSTests
//

import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

/// The completion dwell, the tray and its Undo, as the Mac's Workbench has them.
@MainActor
struct PhoneActionsTests {
    @Test func aTickDwellsThenIsWritten() async throws {
        let phone = try TestPhone(seeded: true)
        phone.env.settings.undoDwellSeconds = 2
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.toggle(task)
        #expect(phone.env.actions.isClosing(task.id))
        #expect(!task.isCompleted)
        #expect(phone.env.tray.message?.text == "Completed “Start Piranesi”")
        #expect(phone.env.tray.message?.actionTitle == "Undo")

        try await Task.sleep(for: .seconds(2.6))
        #expect(task.isCompleted)
        #expect(!phone.env.actions.isClosing(task.id))
        #expect(!phone.store.completionRecords(taskID: task.id).isEmpty)
    }

    /// Undo inside the window writes nothing, so no other device sees a
    /// completion and its undo.
    @Test func undoInTheDwellWritesNothing() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.toggle(task)
        phone.env.tray.performAction()
        #expect(!phone.env.actions.isClosing(task.id))
        phone.env.actions.settleAll()
        #expect(!task.isCompleted)
        #expect(phone.store.completionRecords(taskID: task.id).isEmpty)
    }

    /// Ticking a dwelling row again takes it back, as its Undo would.
    @Test func tickingADwellingRowTakesItBack() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.toggle(task)
        phone.env.actions.toggle(task)
        #expect(!phone.env.actions.isClosing(task.id))
        #expect(phone.env.tray.message == nil)
        phone.env.actions.settleAll()
        #expect(!task.isCompleted)
    }

    @Test func undoAfterTheWriteRestoresTheTask() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.complete([task])
        phone.env.actions.settle(task.id)
        #expect(task.isCompleted)
        phone.env.tray.performAction()
        #expect(!task.isCompleted)
    }

    /// A repeat rolls forward at once; Undo brings its date back.
    @Test func aRepeatRollsForwardAtOnce() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Ask Mika to water the planters"))
        let due = try #require(task.dueDate)
        phone.env.actions.complete([task])
        #expect(!phone.env.actions.isClosing(task.id))
        #expect(try #require(task.dueDate) > due)
        phone.env.tray.performAction()
        #expect(task.dueDate == due)
    }

    @Test func trashHasUndo() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        #expect(phone.env.actions.trash([task]))
        #expect(task.trashID != nil)
        #expect(phone.env.tray.message?.text == "Moved “Start Piranesi” to Trash")
        phone.env.tray.performAction()
        #expect(task.trashID == nil)
        #expect(phone.store.block(id: task.id) != nil)
    }

    @Test func moveHasUndo() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        let reading = try #require(phone.list("Reading"))
        let home = try #require(phone.list("Home"))
        #expect(phone.env.actions.move([task], to: home))
        #expect(task.listID == home.id)
        #expect(phone.env.tray.message?.text == "Moved “Start Piranesi” to Home")
        phone.env.tray.performAction()
        #expect(task.listID == reading.id)
    }

    /// Trash's Restore: "Restored to Home", and Undo sends it back.
    @Test func restoreHasUndo() throws {
        let phone = try TestPhone(seeded: true)
        let kettle = try #require(try phone.store.trashEntries().first { $0.title == "Descale the kettle" })
        #expect(phone.env.actions.restore([kettle.id]))
        #expect(phone.store.block(id: kettle.id) != nil)
        #expect(phone.env.tray.message?.text == "Restored to Home")
        phone.env.tray.performAction()
        #expect(phone.store.block(id: kettle.id) == nil)
        #expect(try phone.store.trashEntries().contains { $0.id == kettle.id })
    }

    @Test func fieldEditsUndoOnlyTheirFields() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.edit([task], "Starred “Start Piranesi”") { $0.isStarred = true }
        #expect(task.isStarred)
        phone.store.setPriority(.high, for: task)
        phone.env.tray.performAction()
        #expect(!task.isStarred)
        #expect(task.priority == .high)
    }

    @Test func aWidgetTickSettlesAtOnce() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.completeFromWidget(task.id, at: TestClock.mockupNow, now: TestClock.mockupNow)
        #expect(task.isCompleted)
        #expect(task.completedAt == TestClock.mockupNow)
    }

    @Test func hapticsFollowTheSetting() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.settings.playsHaptics = false
        phone.env.actions.complete([task])
        #expect(phone.env.haptics.lastPlayed == nil)
        phone.env.settings.playsHaptics = true
        phone.env.actions.toggle(task)
        #expect(phone.env.haptics.lastPlayed == .soft)
    }

    @Test func theTrayReplacesItsMessage() {
        let tray = TrayCenter()
        var undone = 0
        let first = tray.show("First") { undone += 1 }
        let second = tray.show("Second", tone: .danger)
        #expect(tray.message?.id == second.id)
        #expect(!tray.isActionAvailable(for: first.id))
        tray.dismiss(first.id)
        #expect(tray.message?.id == second.id)
        tray.performAction()
        #expect(undone == 0)
        #expect(tray.message == nil)
    }
}
