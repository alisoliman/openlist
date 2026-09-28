//
//  PhoneWork.swift
//  OpenlistiOS
//

import Foundation

/// The work in hand as Today's Now card and Working show it: the running
/// session, else the paused one that can resume, else a task whose slot is
/// on now. Read from the calendar each render, so it never keeps a copy.
@MainActor
struct PhoneWork {
    enum State: Equatable {
        /// Its slot is on now and it hasn't started: play starts it.
        case planned
        case working
        case paused
    }

    var task: Block?
    var state: State = .planned
    /// Where the work is drawn: its slot, or the running block.
    var start: Date?
    var end: Date?
    /// Minutes to go: to its estimate while it runs or is paused, to the end
    /// of its slot while planned.
    var remainingMinutes: Double = 0

    init(env: PhoneEnvironment, now: Date) {
        let calendar = env.calendar
        let blocks = calendar.visibleBlocks
        if let session = calendar.activeSession, let task = env.store.block(id: session.taskID), !task.isCompleted {
            self.task = task
            state = .working
            let block = blocks.first { $0.isActive } ?? blocks.first { $0.occurrenceID == session.occurrenceID && $0.end > now }
            remainingMinutes = calendar.remainingMinutes(for: task, now: now)
            start = block?.start ?? session.startedAt
            end = block?.end ?? now.addingTimeInterval(remainingMinutes * 60)
        } else if let task = calendar.resumableTask {
            self.task = task
            state = .paused
            let block = blocks.first { $0.id == calendar.pausedBlockID }
                ?? blocks.first { $0.occurrenceID == task.occurrenceID && !$0.isCompleted }
            remainingMinutes = calendar.remainingMinutes(for: task, now: now)
            start = block?.start
            end = block?.end
        } else if let block = blocks.first(where: { block in
            // Not one just ticked, which is done as far as the screens go.
            !block.isCompleted && block.start <= now && now < block.end && !env.actions.isClosing(block.taskID)
                && env.store.block(id: block.taskID).map { !$0.isCompleted && $0.occurrenceID == block.occurrenceID } == true
        }), let task = env.store.block(id: block.taskID) {
            self.task = task
            state = .planned
            start = block.start
            end = block.end
            remainingMinutes = max(0, block.end.timeIntervalSince(now) / 60)
        }
    }

    /// "50 min left", counting a started minute as left.
    var leftText: String { "\(minutesLeft) min left" }

    var minutesLeft: Int { max(0, Int(remainingMinutes.rounded(.up))) }

    /// How far through its block the work is, 0–1: by the minutes left while
    /// it runs or is paused, so a paused bar holds still; by the clock while
    /// its slot is only planned.
    func progress(now: Date) -> Double {
        guard let start, let end, end > start else { return 0 }
        let length = end.timeIntervalSince(start)
        let passed = state == .planned ? now.timeIntervalSince(start) : length - remainingMinutes * 60
        return min(1, max(0, passed / length))
    }

    /// Today's Now card, when there's work in hand.
    var card: (eyebrow: String, title: String, detail: String, state: OLNowCard.State)? {
        guard let task else { return nil }
        let eyebrow = start.map { "Now · \(CompactText.clock($0))" } ?? "Now"
        let cardState: OLNowCard.State = switch state {
        case .planned: .planned
        case .working: .working
        case .paused: .paused
        }
        return (eyebrow, task.displayTitle, leftText, cardState)
    }

    /// The Now card's play: starts or resumes the work, then opens Working.
    func play(_ env: PhoneEnvironment) {
        guard let task else { return }
        if state != .working { guard env.actions.startWork(task) else { return } }
        env.navigator.open(.working)
    }

    /// Where each task sits on the calendar on `day`: its earliest drawn block
    /// that isn't done, for Today's order and times.
    static func slots(_ calendar: CalendarCoordinator, on day: Date, calendar dates: Calendar) -> [UUID: Date] {
        var slots: [UUID: Date] = [:]
        for block in calendar.visibleBlocks where !block.isCompleted && dates.isDate(block.start, inSameDayAs: day) {
            if let existing = slots[block.taskID], existing <= block.start { continue }
            slots[block.taskID] = block.start
        }
        return slots
    }
}
