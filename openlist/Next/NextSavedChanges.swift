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
}
