//
//  NextLogWrites.swift
//  openlist
//
//  When the change log's own changes reached saved history, so Changes can
//  tell that history from edits made elsewhere.
//

import Foundation

/// Each moment the log's changes were written, undone or redone, in time
/// order, with the tasks and lists they covered; and each span a list
/// document line was written over, whose typing saves as it goes and which
/// the log records once, as the line ends, or not at all, as a new line left
/// empty goes.
struct NXLogWrites {
    private var points: [(at: Date, ids: Set<UUID>)] = []
    private var spans: [(from: Date, to: Date, ids: Set<UUID>)] = []

    /// A change, its Undo or its Redo, written at `date`. One that covers
    /// nothing accounts for everything saved around it.
    mutating func note(_ ids: Set<UUID>, at date: Date = .now) {
        points.append((date, ids))
        if points.count > 1000 { points.removeFirst(points.count - 1000) }
    }

    /// A line written from `start` until `end`, touching `ids`.
    mutating func note(_ ids: Set<UUID>, from start: Date, to end: Date = .now) {
        guard !ids.isEmpty else { return }
        spans.append((start, end, ids))
        if spans.count > 500 { spans.removeFirst(spans.count - 500) }
    }

    /// Whether saved history from `date` about a task or list came from one
    /// of these writes. A write accounts for what it covered, saved from 2 s
    /// before it to 3 s after; one that covered nothing, for all of it. A
    /// line accounts for what it touched from 2 s before it began to 3 s
    /// after it ended.
    func wrote(at date: Date, about ids: [UUID?]) -> Bool {
        let from = date.addingTimeInterval(-3), to = date.addingTimeInterval(2)
        func covers(_ covered: Set<UUID>) -> Bool { ids.contains { $0.map(covered.contains) == true } }
        // Points are in time order; start at the first one late enough.
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].at < from { low = mid + 1 } else { high = mid }
        }
        if points[low...].prefix(while: { $0.at <= to }).contains(where: { $0.ids.isEmpty || covers($0.ids) }) {
            return true
        }
        return spans.contains { $0.to >= from && $0.from <= to && covers($0.ids) }
    }
}
