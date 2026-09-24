//
//  NextLogWrites.swift
//  openlist
//
//  When the change log's own changes reached saved history, so Changes can
//  tell that history from edits made elsewhere.
//

import Foundation

/// Each moment the log's changes were written, undone or redone, in time
/// order, with the tasks and lists they covered. A list document line's end
/// is one too: saved history takes the line's one entry then, which the log
/// records as the design does, or not at all, as a new line left empty goes.
struct NXLogWrites {
    private var points: [(at: Date, ids: Set<UUID>)] = []

    /// A change, its Undo or its Redo, written at `date`. One that covers
    /// nothing accounts for everything saved around it.
    mutating func note(_ ids: Set<UUID>, at date: Date = .now) {
        points.append((date, ids))
        if points.count > 1000 { points.removeFirst(points.count - 1000) }
    }

    /// Whether saved history from `date` about a task or list came from one
    /// of these writes. A write accounts for what it covered, saved from 2 s
    /// before it to 3 s after; one that covered nothing, for all of it.
    func wrote(at date: Date, about ids: [UUID?]) -> Bool {
        let from = date.addingTimeInterval(-3), to = date.addingTimeInterval(2)
        func covers(_ covered: Set<UUID>) -> Bool { ids.contains { $0.map(covered.contains) == true } }
        // Points are in time order; start at the first one late enough.
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].at < from { low = mid + 1 } else { high = mid }
        }
        return points[low...].prefix(while: { $0.at <= to }).contains { $0.ids.isEmpty || covers($0.ids) }
    }
}
