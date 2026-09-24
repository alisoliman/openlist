//
//  NextCommands.swift
//  openlist
//
//  Task-menu commands with no design action of their own. They act on the
//  workbench targets and land in the tray and Undo like every other change.
//

import Foundation

extension AppEnvironment {
    /// Runs a Task-menu command on `ids` the way the Next screens do, with
    /// the workbench's dwell, tray, log and Undo. `false` for the outline's
    /// own commands, which only a document can run.
    @discardableResult
    func performTaskCommand(_ command: EditorCommand, on ids: [UUID]) -> Bool {
        switch command {
        case .newTask:
            workbench.openCapture()
        case .toggleCompletion:
            workbench.toggleCompletion(ids)
        case .openDetails:
            if let first = ids.first { inspectForCommand(first) }
        case .pickDueDate, .pickLabel:
            guard let first = ids.first else { return true }
            requestedPicker = command == .pickDueDate ? .due : .labels
            inspectForCommand(first)
        case .setDueToday:
            workbench.schedule(ids, offset: 0)
        case .clearDueDate:
            workbench.schedule(ids, offset: nil)
        case .toggleStar:
            workbench.star(ids)
        case .deleteSelection:
            workbench.trash(ids)
        case .clearLabels:
            workbench.clearLabels(ids)
        case .indent, .outdent, .moveUp, .moveDown, .expandAll, .collapseAll:
            return false
        }
        return true
    }

    /// Opens a task in the inspector. The task already on show keeps the focus
    /// it has, so the Inbox triage keys still work once the inspector closes.
    private func inspectForCommand(_ id: UUID) {
        guard id != navigator.openTaskID else { return }
        workbench.inspect(id)
    }
}

extension Workbench {
    /// Task ▸ Clear Labels: strips every target's labels as one undoable change.
    func clearLabels(_ ids: [UUID]) {
        let tasks = tasks(ids).filter { !$0.labelIDs.isEmpty }
        guard !tasks.isEmpty else { return }
        let before = tasks.map { (id: $0.id, labelIDs: $0.labelIDs) }
        let cleared = before.map { (id: $0.id, labelIDs: [UUID]()) }
        let label = "Cleared labels on \(describe(tasks))"
        store.batch { for task in tasks { store.clearLabels(on: task) } }
        registerUndo(label, undo: { $0.applyLabelIDs(before) }, redo: { $0.applyLabelIDs(cleared) })
        snap(label, icon: "tag", tone: .accent, ids: tasks.map(\.id))
    }

    private func applyLabelIDs(_ changes: [(id: UUID, labelIDs: [UUID])]) {
        for change in changes {
            guard let task = store.block(id: change.id) else { continue }
            task.labelIDs = change.labelIDs
            task.touch()
        }
        store.save()
        markRestored(changes.map(\.id))
    }
}
