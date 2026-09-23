//
//  NextCommands.swift
//  openlist
//
//  Task-menu commands with no design action of their own. They act on the
//  workbench targets and land in the tray and Undo like every other change.
//

import Foundation

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
