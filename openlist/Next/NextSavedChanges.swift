//
//  NextSavedChanges.swift
//  openlist
//
//  Saved history read back as the changes the log shows.
//

import Foundation

/// What Changes groups a saved event by. A change the log shows as one row,
/// a task trashed with its subtasks or three tasks moved, saves an event for
/// each task, all in one batch, so it reads as one row after a relaunch too.
struct NXSavedFact {
    /// The change that saved it; nil for history saved before batches and
    /// for a list document line's, which the log records a line each.
    var batch: UUID?
    /// The event's kind.
    var kind: String
    /// Events of one batch with the same key share a row; nil shares none.
    var key: String?
    /// The kind of its tasks' events a list's own event takes into its row:
    /// a list trashed, copied or restored is one change, as the log says.
    var takes: String?
}

/// A task's event in one change's row, as the row counts it.
struct NXSavedTask {
    var id: UUID?
    /// A repeat that rolled on to its next date, resetting its subtasks.
    var rolls = false
}

enum NXSavedChanges {
    /// `facts`, newest first, as rows of their indexes, newest first by the
    /// newest event each holds. A row starts with the event that names it:
    /// the list's own, or the newest of the tasks'.
    static func rows(_ facts: [NXSavedFact]) -> [[Int]] {
        // Each batch's list event for the kind it takes in.
        var takers: [UUID: [String: Int]] = [:]
        for (index, fact) in facts.enumerated() {
            guard let batch = fact.batch, let takes = fact.takes, takers[batch]?[takes] == nil else { continue }
            takers[batch, default: [:]][takes] = index
        }
        var rows: [[Int]] = []
        var shared: [String: Int] = [:]
        var taken: [Int: Int] = [:]
        func row(of taker: Int) -> Int {
            if let row = taken[taker] { return row }
            rows.append([taker])
            taken[taker] = rows.count - 1
            return rows.count - 1
        }
        for (index, fact) in facts.enumerated() {
            if let batch = fact.batch, let taker = takers[batch]?[fact.kind], taker != index {
                rows[row(of: taker)].append(index)
            } else if fact.takes != nil, fact.batch != nil {
                _ = row(of: index)
            } else if let batch = fact.batch, let key = fact.key {
                let id = "\(batch)|\(key)"
                if let row = shared[id] {
                    rows[row].append(index)
                } else {
                    shared[id] = rows.count
                    rows.append([index])
                }
            } else {
                rows.append([index])
            }
        }
        return rows
    }

    /// The events of one change's row the log counts, as their indexes, the
    /// log's way: a move, a restore or an add counts the tasks it was about,
    /// not the subtasks that went with them; a completion every task that
    /// closed, subtasks too, but those a repeat reset as it rolled on, as the
    /// log counts a repeat and the rest that close; anything else, each task.
    /// `parent` gives a task's parent.
    static func counted(_ tasks: [NXSavedTask], kind: String, parent: (UUID) -> UUID?) -> [Int] {
        switch kind {
        case "moved", "restored", "created":
            let ids = Set(tasks.compactMap(\.id))
            return tasks.indices.filter { tasks[$0].id.flatMap(parent).map(ids.contains) != true }
        case "completed":
            let rolled = Set(tasks.filter(\.rolls).compactMap(\.id))
            guard !rolled.isEmpty else { return Array(tasks.indices) }
            return tasks.indices.filter { index in
                var next = tasks[index].id.flatMap(parent)
                var visited: Set<UUID> = []
                while let id = next, visited.insert(id).inserted {
                    if rolled.contains(id) { return false }
                    next = parent(id)
                }
                return true
            }
        default:
            return Array(tasks.indices)
        }
    }
}
