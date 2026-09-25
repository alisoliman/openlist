//
//  UpNext.swift
//  OpenlistWidget
//

import Foundation

/// What the Up Next widget shows at one moment.
///
/// A running or paused work session always wins, because it is what the
/// toolbar timer in the app shows too. Otherwise the widget follows today's
/// plan: the block under way, else the next one.
nonisolated struct UpNext: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case working
        case paused
        /// A planned block is under way but nothing is recording.
        case now
        /// The next planned block later today.
        case next
        /// Nothing else planned today.
        case none
    }

    /// One row of "Later today".
    struct Later: Equatable, Identifiable, Sendable {
        var id: String
        var start: Date
        var title: String
        /// "11:30".
        var time: String
        /// The task's list colour; `nil` for meetings, which draw `track`.
        var accentHex: UInt32?
        var isMeeting: Bool
    }

    let phase: Phase
    let taskID: UUID?
    let occurrenceID: UUID?
    let title: String
    let listIcon: String
    let listName: String
    let accentHex: UInt32?
    let start: Date?
    let end: Date?
    /// "10:00–11:30", or empty when the session has no planned block today.
    let rangeText: String
    /// 0...1. Recording: time recorded against the estimate. Now: how much of
    /// the block has passed. Next and none: 0.
    let progress: Double
    /// "50 min left", "in 50 min", or "of 90 min" while recording.
    let note: String
    /// Recorded seconds at this moment.
    let elapsed: TimeInterval
    /// While working, the date to count from with `Text(timerInterval:)`, so
    /// the clock ticks without timeline reloads.
    let timerOrigin: Date?
    let later: [Later]

    var isRecording: Bool { phase == .working || phase == .paused }

    /// "NOW", "NEXT", "WORKING", "PAUSED" before uppercasing.
    var phaseLabel: String {
        switch phase {
        case .working: "Working"
        case .paused: "Paused"
        case .now: "Now"
        case .next: "Next"
        case .none: "Up next"
        }
    }

    /// "💼 Q3 planning"; pass `includesIcon: !style.isVibrant`.
    func listLine(includesIcon: Bool = true) -> String {
        WidgetFormat.listLine(icon: listIcon, name: listName, includesIcon: includesIcon)
    }

    init(snapshot: WidgetSnapshot, now: Date, calendar: Calendar = .current) {
        let today = snapshot.agenda.filter { calendar.isDate($0.start, inSameDayAs: now) }
        let blocks = today
            .filter { $0.kind == .task && $0.taskID != nil && !$0.isCompleted }
            .sorted { $0.start < $1.start }
        // The block the header shows, which "Later today" leaves out.
        let current: WidgetSnapshot.AgendaEvent?
        // "Later today" starts where the time the header holds ends: the
        // block under way, or running work's. Otherwise it starts now.
        let laterFrom: Date

        if let work = snapshot.work {
            // The session's slot belongs in the header only when it is on
            // today's plan: paused work carries its next planned block, which
            // can be days away. Without one, the task's block under way
            // stands in; a later block is not what the session records into.
            let slotIsToday = work.blockStart.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            let own = blocks.filter { $0.taskID == work.taskID }
            let block = own.first { $0.start == work.blockStart } ?? own.first { $0.start <= now && now < $0.end }
            let estimate = work.estimateMinutes * 60
            phase = work.state == .working ? .working : .paused
            taskID = work.taskID
            occurrenceID = work.occurrenceID
            title = work.title
            listIcon = work.listIcon
            listName = work.listName
            accentHex = work.accentHex
            start = (slotIsToday ? work.blockStart : nil) ?? block?.start
            end = (slotIsToday ? work.blockEnd : nil) ?? block?.end
            elapsed = work.elapsed(at: now)
            progress = estimate > 0 ? min(1, elapsed / estimate) : 0
            note = estimate > 0 ? "of \(Int((estimate / 60).rounded())) min" : ""
            timerOrigin = work.state == .working ? work.timerOrigin : nil
            current = block
            // Running work holds its block until the block ends. Paused work
            // holds no time, so everything still ahead today is later.
            if work.state == .working, let start, let end, start <= now {
                laterFrom = max(end, now)
            } else {
                laterFrom = now
            }
        } else if let block = blocks.first(where: { $0.start <= now && now < $0.end }) ?? blocks.first(where: { $0.start > now }) {
            let isNow = block.start <= now
            phase = isNow ? .now : .next
            taskID = block.taskID
            occurrenceID = block.occurrenceID
            title = block.title
            listIcon = block.listIcon
            listName = block.listName
            accentHex = block.accentHex
            start = block.start
            end = block.end
            elapsed = 0
            let length = block.end.timeIntervalSince(block.start)
            progress = isNow && length > 0 ? min(1, now.timeIntervalSince(block.start) / length) : 0
            note = isNow ? WidgetFormat.minutesLeft(until: block.end, now: now) : WidgetFormat.minutesUntil(block.start, now: now)
            timerOrigin = nil
            current = block
            // A block still to come holds no time yet: meetings before it are
            // ahead too, and the planner fits blocks around them.
            laterFrom = isNow ? block.end : now
        } else {
            // Only meetings can be left without a block. The subtitle names
            // the next, as the small family has no Later column, and says the
            // day is clear only when nothing is: `later` holds the same events.
            let ahead = today
                .filter { !$0.isCompleted && $0.start >= now }
                .min { ($0.start, $0.title) < ($1.start, $1.title) }
            phase = .none
            taskID = nil
            occurrenceID = nil
            title = "Nothing else planned"
            listIcon = ""
            listName = ahead.map { "Next: \($0.title) at \(WidgetFormat.clock($0.start, calendar: calendar))" } ?? "Your day is clear"
            accentHex = nil
            start = nil
            end = nil
            elapsed = 0
            progress = 0
            note = ""
            timerOrigin = nil
            current = nil
            laterFrom = now
        }

        if let start, let end {
            rangeText = WidgetFormat.range(start, end, calendar: calendar)
        } else {
            rangeText = ""
        }
        later = today
            .filter { $0.id != current?.id && !$0.isCompleted && $0.start >= laterFrom }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            .map {
                Later(id: $0.id, start: $0.start, title: $0.title, time: WidgetFormat.clock($0.start, calendar: calendar),
                      accentHex: $0.kind == .meeting ? nil : $0.accentHex, isMeeting: $0.kind == .meeting)
            }
    }
}
