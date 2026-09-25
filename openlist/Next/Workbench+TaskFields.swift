//
//  Workbench+TaskFields.swift
//  openlist
//

import Foundation

/// The fields a design action can change, captured so Undo can put them back.
struct TaskFields {
    var id: UUID
    var dueDate: Date?
    var includesTime: Bool
    var reminderAt: Date?
    var isStarred: Bool
    var priorityRaw: Int
    var recurrenceData: Data?
    var labelIDs: [UUID]
    var selectedForDay: Date?
    var deferredUntil: Date?
    var estimate: Int

    init(_ block: Block) {
        id = block.id
        dueDate = block.dueDate
        includesTime = block.includesTime
        reminderAt = block.reminderAt
        isStarred = block.isStarred
        priorityRaw = block.priorityRaw
        recurrenceData = block.recurrenceData
        labelIDs = block.labelIDs
        selectedForDay = block.selectedForDay
        deferredUntil = block.deferredUntil
        estimate = block.schedulingEstimateMinutes
    }

    /// Puts the fields back. Given the fields they replace, it writes only
    /// those that differ, the ones the step changed, so Undo and Redo leave
    /// alone whatever else changed in the task meanwhile.
    func apply(to block: Block, replacing replaced: TaskFields?) {
        func put<Value: Equatable>(_ field: KeyPath<TaskFields, Value>, _ write: (Value) -> Void) {
            if replaced.map({ $0[keyPath: field] != self[keyPath: field] }) ?? true { write(self[keyPath: field]) }
        }
        put(\.dueDate) { block.dueDate = $0 }
        put(\.includesTime) { block.includesTime = $0 }
        put(\.reminderAt) { block.reminderAt = $0 }
        put(\.isStarred) { block.isStarred = $0 }
        put(\.priorityRaw) { block.priorityRaw = $0 }
        put(\.recurrenceData) { block.recurrenceData = $0 }
        put(\.labelIDs) { block.labelIDs = $0 }
        put(\.selectedForDay) { block.selectedForDay = $0 }
        put(\.deferredUntil) { block.deferredUntil = $0 }
        put(\.estimate) { block.schedulingEstimateMinutes = $0 }
        block.touch()
    }
}
