//
//  WidgetState.swift
//  OpenlistWidget
//

import Foundation

/// How a task's checkbox should look.
nonisolated enum TaskCheck: Equatable, Sendable {
    case open
    /// Ticked in the widget; the app has not applied it yet.
    case closing
    case done
}

/// The snapshot as a widget should draw it at one moment.
///
/// Two things can make the published snapshot out of date. Commands queued by
/// widget buttons have not reached the app yet, so their effect is layered on
/// here; the app removes a command once applied, which makes replaying every
/// pending one idempotent. And counters were computed when the app wrote the
/// file, possibly hours ago, while rows judge lateness at the entry's date, so
/// past midnight the late and done counts are brought forward to that date
/// too, and the next day's published work becomes today's.
nonisolated struct WidgetState: Equatable, Sendable {
    private(set) var snapshot: WidgetSnapshot
    /// Occurrences ticked off in the widget and still waiting for the app.
    private(set) var closing: Set<UUID> = []
    let now: Date
    /// The Mac's calendar with the app's first weekday.
    let calendar: Calendar

    init(snapshot: WidgetSnapshot, pending: [WidgetCommand] = [], now: Date, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = snapshot.calendar(base: calendar)
        bringCountsForward()
        for command in pending.sorted(by: { $0.issuedAt < $1.issuedAt }) {
            apply(command)
        }
    }

    // MARK: - Reading

    /// The app has not republished for two days or more, so the day's own
    /// work is unknown: only what it published for today and tomorrow could
    /// be carried forward. A widget should ask for the app rather than call
    /// the day clear.
    var isOutdated: Bool {
        WidgetFormat.dayOffset(from: snapshot.generatedAt, to: now, calendar: calendar) >= 2
    }

    func check(for item: WidgetSnapshot.Item) -> TaskCheck {
        if closing.contains(item.occurrenceID) { return .closing }
        return item.isCompleted ? .done : .open
    }

    func isClosing(_ item: WidgetSnapshot.Item) -> Bool {
        closing.contains(item.occurrenceID)
    }

    func dueText(for item: WidgetSnapshot.Item) -> String {
        WidgetFormat.dueText(for: item, now: now, calendar: calendar)
    }

    /// Today's rows: late work, then the rest of today, each in the app's
    /// order, `limit` in all. Late work leaves two rows to today's when there
    /// are that many, so a long backlog never pushes the day's own work out
    /// of the large widget's sections. A row keeps its section while it is
    /// being ticked off, so the rows don't reshuffle before the app settles it.
    func todaySections(limit: Int = .max) -> (late: [WidgetSnapshot.Item], rest: [WidgetSnapshot.Item]) {
        let late = snapshot.todayItems.filter { $0.isOverdue(at: now, calendar: calendar) }
        let rest = snapshot.todayItems.filter { !$0.isOverdue(at: now, calendar: calendar) }
        let lateShown = min(late.count, max(0, limit - min(2, rest.count)))
        return (Array(late.prefix(lateShown)), Array(rest.prefix(max(0, limit - lateShown))))
    }

    /// "2 of 9 done": today's completions against everything due by today.
    var todayProgress: (done: Int, total: Int) {
        let done = snapshot.completedTodayCount
        return (done, done + snapshot.overdueCount + snapshot.dueTodayCount)
    }

    /// Up Next's block and the rest of the day, at this entry's date.
    var upNext: UpNext {
        UpNext(snapshot: snapshot, now: now, calendar: calendar)
    }

    // MARK: - Time

    private mutating func bringCountsForward() {
        let written = snapshot.generatedAt
        // Lateness goes by day, as the app's Today counts it, so nothing
        // turns late before midnight.
        guard now > written, !calendar.isDate(now, inSameDayAs: written) else { return }
        snapshot.completedTodayCount = 0
        startNextDay()
        // Midnight passing makes the day's work late; the counters follow.
        // `dueToday` holds every task behind the count, where the rows stop
        // at the display cap.
        let calendar = calendar, now = now
        let turned = { (due: WidgetSnapshot.Due) in
            !due.isOverdue(at: written, calendar: calendar) && due.isOverdue(at: now, calendar: calendar)
        }
        let late = snapshot.dueToday.count(where: turned)
        snapshot.overdueCount += late
        snapshot.dueTodayCount = max(0, snapshot.dueTodayCount - late)
        snapshot.dueToday.removeAll(where: turned)
    }

    /// The app republishes at midnight only while it runs, so the snapshot
    /// carries the day after it was written: its work becomes today's here,
    /// while the day before's turns late in the pass above. Two days on,
    /// that is late too; what the second day holds is not published.
    private mutating func startNextDay() {
        // Tomorrow's rows are today's now, after the day before's, which are
        // all late. The app caps the overdue, due-today and tomorrow rows
        // separately, each at more than a widget draws, so rows a cap left
        // out never come before the rows a widget shows.
        snapshot.todayItems += snapshot.tomorrowItems
        // Both are soonest first, and tomorrow's all come later.
        snapshot.dueToday += snapshot.dueTomorrow
        snapshot.dueTodayCount += snapshot.dueTomorrow.count
        // Merged once: a tick or reopen then finds them only as today's.
        snapshot.tomorrowItems = []
        snapshot.dueTomorrow = []
    }

    // MARK: - Pending commands

    private mutating func apply(_ command: WidgetCommand) {
        // The app refuses work commands once they are stale, and drops every
        // command at the end of the queue's lifetime; drawing one then would
        // show a clock that never runs, or a tick that never lands.
        guard command.isCurrent(at: now) else { return }
        // Every button names the task and occurrence it drew, and the app
        // acts on nothing a command fails to name, so neither does this.
        guard let taskID = command.taskID, let occurrence = command.occurrenceID else { return }
        // As the app dates it: at the tap, or now when the clock has been set
        // back since and put the tap in the future.
        let tappedAt = min(now, command.issuedAt)
        switch command.action {
        case .complete:
            complete(taskID, occurrence: occurrence, tappedAt: tappedAt)
        case .finishWork:
            guard isWork(taskID, occurrence) else { return }
            complete(taskID, occurrence: occurrence, tappedAt: tappedAt)
            snapshot.work = nil
        case .reopen:
            reopen(taskID, occurrence: occurrence)
        case .startWork:
            startWork(taskID, occurrence: occurrence, at: tappedAt)
        case .pauseWork:
            if isWork(taskID, occurrence) { pauseWork(at: tappedAt) }
        case .resumeWork:
            if isWork(taskID, occurrence) { resumeWork(at: tappedAt) }
        }
    }

    /// Whether a Pause, Resume or Done was aimed at the work there is. The
    /// buttons name the session the widget drew, and the app ignores one that
    /// no longer matches the work it has, so a tap from a stale widget draws
    /// nothing either.
    private func isWork(_ taskID: UUID, _ occurrence: UUID) -> Bool {
        snapshot.work.map { $0.taskID == taskID && $0.occurrenceID == occurrence } ?? false
    }

    private mutating func complete(_ taskID: UUID, occurrence: UUID, tappedAt: Date) {
        let closing = self.closing
        func matches(_ item: WidgetSnapshot.Item) -> Bool {
            item.id == taskID && item.occurrenceID == occurrence && !item.isCompleted && !closing.contains(item.occurrenceID)
        }
        let row = (snapshot.todayItems + snapshot.lists.flatMap(\.openItems)).first(where: matches)
        let block = snapshot.agenda.firstIndex { $0.taskID == taskID && $0.occurrenceID == occurrence && !$0.isCompleted }
        let endsWork = isWork(taskID, occurrence)
        // Nothing open to tick: the app already applied it, or the task is
        // not shown anywhere. Either way, counting it again would be wrong.
        guard row != nil || block != nil || endsWork, !closing.contains(occurrence) else { return }
        // The app rolls a repeat forward rather than complete it: it stays
        // open, off Done today and out of its list's completed rows. Its
        // rows share the flag, whichever occurrence they show.
        let repeats = row?.hasRepeat ?? allRows.first { $0.id == taskID }?.hasRepeat ?? false

        self.closing.insert(occurrence)
        if let row, let due = row.dueDate, WidgetFormat.dayOffset(from: now, to: due, calendar: calendar) <= 0 {
            if row.isOverdue(at: now, calendar: calendar) {
                snapshot.overdueCount = max(0, snapshot.overdueCount - 1)
            } else {
                snapshot.dueTodayCount = max(0, snapshot.dueTodayCount - 1)
                // Tasks due at the same moment are interchangeable here.
                if let index = snapshot.dueToday.firstIndex(of: WidgetSnapshot.Due(date: due, includesTime: row.includesTime)) {
                    snapshot.dueToday.remove(at: index)
                }
            }
        }
        if !repeats {
            // Done today is the entry's day, and the app dates the completion
            // at the tap: a tick queued before midnight belongs to the day before.
            if calendar.isDate(tappedAt, inSameDayAs: now) { snapshot.completedTodayCount += 1 }
            snapshot.totalOpenCount = max(0, snapshot.totalOpenCount - 1)
            let listID = row?.listID ?? snapshot.lists.first { $0.openItems.contains { $0.id == taskID } }?.id
            if let index = snapshot.lists.firstIndex(where: { $0.id == listID }) {
                snapshot.lists[index].openCount = max(0, snapshot.lists[index].openCount - 1)
                snapshot.lists[index].doneCount += 1
            }
        }
        for index in snapshot.agenda.indices where snapshot.agenda[index].taskID == taskID && snapshot.agenda[index].occurrenceID == occurrence {
            snapshot.agenda[index].isCompleted = true
            snapshot.agenda[index].isActive = false
        }
        if endsWork { snapshot.work = nil }
        // An Inbox capture ticked from a List widget leaves the Inbox too.
        if let index = snapshot.inboxItems.firstIndex(where: { $0.id == taskID }) {
            snapshot.inboxItems.remove(at: index)
            snapshot.inboxCount = max(0, snapshot.inboxCount - 1)
        }
        // Activity counts every completion, repeats included.
        recordCompletion(on: tappedAt)
    }

    /// Every task row the snapshot carries, open or done.
    private var allRows: [WidgetSnapshot.Item] {
        snapshot.todayItems + snapshot.tomorrowItems + snapshot.lists.flatMap { $0.openItems + $0.doneItems }
    }

    private mutating func reopen(_ taskID: UUID, occurrence: UUID) {
        func matches(_ item: WidgetSnapshot.Item) -> Bool {
            item.id == taskID && item.occurrenceID == occurrence && item.isCompleted
        }
        var reopened: WidgetSnapshot.Item?
        func markOpen(_ item: inout WidgetSnapshot.Item) {
            guard matches(item) else { return }
            reopened = reopened ?? item
            item.isCompleted = false
            item.completedAt = nil
        }
        for index in snapshot.todayItems.indices { markOpen(&snapshot.todayItems[index]) }
        for list in snapshot.lists.indices {
            for index in snapshot.lists[list].openItems.indices { markOpen(&snapshot.lists[list].openItems[index]) }
            // A reopened row leaves the completed section for the open one.
            while let index = snapshot.lists[list].doneItems.firstIndex(where: matches) {
                var item = snapshot.lists[list].doneItems.remove(at: index)
                markOpen(&item)
                snapshot.lists[list].openItems.append(item)
                snapshot.lists[list].openCount += 1
                snapshot.lists[list].doneCount = max(0, snapshot.lists[list].doneCount - 1)
            }
        }
        guard let item = reopened else { return }
        closing.remove(item.occurrenceID)
        snapshot.totalOpenCount += 1
        if let due = item.dueDate, WidgetFormat.dayOffset(from: now, to: due, calendar: calendar) <= 0 {
            var open = item
            open.isCompleted = false
            if open.isOverdue(at: now, calendar: calendar) {
                snapshot.overdueCount += 1
            } else {
                snapshot.dueTodayCount += 1
                // So it still turns late at midnight.
                let entry = WidgetSnapshot.Due(date: due, includesTime: item.includesTime)
                snapshot.dueToday.insert(entry, at: snapshot.dueToday.firstIndex { $0.date > due } ?? snapshot.dueToday.endIndex)
            }
        }
        // The app takes a reopened task's done block off the calendar, and
        // plans it afresh under a new occurrence, so its blocks go here too.
        snapshot.agenda.removeAll { $0.taskID == taskID && $0.occurrenceID == occurrence }
        // Done today follows the task's state, as the app counts it, and the
        // heatmap takes the completion back, as the Activity screen does.
        if let completedAt = item.completedAt {
            if calendar.isDate(completedAt, inSameDayAs: now) {
                snapshot.completedTodayCount = max(0, snapshot.completedTodayCount - 1)
            }
            removeCompletion(on: completedAt)
        }
    }

    private mutating func startWork(_ taskID: UUID, occurrence: UUID, at date: Date) {
        // A task ticked off in the widget is done by the time the app sees the Start.
        guard !closing.contains(occurrence) else { return }
        if let work = snapshot.work {
            if work.taskID == taskID {
                if work.occurrenceID == occurrence, work.state == .paused { resumeWork(at: date) }
                return
            }
            // Taking over from other running work needs the app's
            // confirmation, so the app ignores this Start from a stale widget.
            if work.state == .working { return }
        }
        let todayBlocks = snapshot.agenda.filter {
            $0.kind == .task && $0.taskID == taskID && $0.occurrenceID == occurrence && !$0.isCompleted
                && calendar.isDate($0.start, inSameDayAs: date)
        }
        // Only the block under way is the session's slot. Starting ahead of a
        // block replans it from the moment of Start, so a later block's times
        // would be wrong in the header; its length is still the best estimate.
        let slot = todayBlocks.first { $0.start <= date && date < $0.end }
        let block = slot ?? todayBlocks.first { $0.start > date } ?? todayBlocks.last
        let row = (snapshot.todayItems + snapshot.lists.flatMap(\.openItems)).first { $0.id == taskID && $0.occurrenceID == occurrence }
        guard let title = block?.title ?? row?.title else { return }
        snapshot.work = WidgetSnapshot.Work(
            state: .working,
            taskID: taskID,
            occurrenceID: occurrence,
            title: title,
            listName: block?.listName ?? row?.listName ?? "",
            listIcon: block?.listIcon ?? row?.listIcon ?? "",
            accentHex: block?.accentHex ?? row?.accentHex ?? snapshot.accentHex,
            segmentStartedAt: date,
            priorSeconds: 0,
            // The app falls back to its default estimate; half an hour is the
            // closest guess the widget can make without it.
            estimateMinutes: block.map { $0.end.timeIntervalSince($0.start) / 60 } ?? 30,
            blockStart: slot?.start,
            blockEnd: slot?.end
        )
        markActiveBlock(at: date)
    }

    private mutating func pauseWork(at date: Date) {
        guard var work = snapshot.work, work.state == .working else { return }
        work.priorSeconds = work.elapsed(at: date)
        work.segmentStartedAt = nil
        work.state = .paused
        snapshot.work = work
        markActiveBlock(at: date)
    }

    private mutating func resumeWork(at date: Date) {
        guard var work = snapshot.work, work.state == .paused else { return }
        work.segmentStartedAt = date
        work.state = .working
        // The app publishes paused work with its next planned block, which
        // can be hours or days away. Resuming, like Start, replans from the
        // moment of the tap, so only a block under way stays the session's slot.
        if let start = work.blockStart, let end = work.blockEnd, !(start <= date && date < end) {
            work.blockStart = nil
            work.blockEnd = nil
        }
        snapshot.work = work
        markActiveBlock(at: date)
    }

    /// Only a running session records into a block: its own slot, or without
    /// one, the task's block under way at `date`. Never a finished block.
    private mutating func markActiveBlock(at date: Date) {
        let work = snapshot.work
        for index in snapshot.agenda.indices {
            let event = snapshot.agenda[index]
            guard let work, work.state == .working, event.taskID == work.taskID, !event.isCompleted else {
                snapshot.agenda[index].isActive = false
                continue
            }
            snapshot.agenda[index].isActive = work.blockStart.map { event.start == $0 } ?? (event.start <= date && date < event.end)
        }
    }

    /// Keeps the heatmap and its totals in step with a completion made from
    /// the widget, on the day the app records it: the day of the tap.
    private mutating func recordCompletion(on date: Date) {
        var activity = snapshot.activity
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        // Without published days, today's total says whether today had any.
        var before = activity.days.isEmpty && day == today ? activity.today : 0
        if let index = activity.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            before = activity.days[index].count
            activity.days[index].count += 1
        } else if let first = activity.days.first, first.date <= day {
            // Today, or a day the app has not published since. Never before
            // the first day: the history starts on a week boundary.
            activity.days.insert(.init(date: day, count: 1), at: activity.days.firstIndex { $0.date > day } ?? activity.days.endIndex)
        }
        // The totals are only read without published days, and then only
        // for the entry's day, week and month.
        if day == today { activity.today += 1 }
        if calendar.isDate(day, equalTo: today, toGranularity: .weekOfYear) { activity.week += 1 }
        if calendar.isDate(day, equalTo: today, toGranularity: .month) { activity.month += 1 }
        // Today only joins the streak once something is done.
        if day == today, before == 0 { activity.streak += 1 }
        snapshot.activity = activity
    }

    /// Takes a reopened completion back off the heatmap and its totals, on
    /// the day it was made, as the app's heatmap does.
    private mutating func removeCompletion(on date: Date) {
        var activity = snapshot.activity
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        // Without published days, today's total says whether today has any left.
        var left = activity.days.isEmpty && day == today ? max(0, activity.today - 1) : nil
        if let index = activity.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            activity.days[index].count = max(0, activity.days[index].count - 1)
            left = activity.days[index].count
        }
        // The totals are only read without published days, and then only
        // for the entry's day, week and month.
        if day == today { activity.today = max(0, activity.today - 1) }
        if calendar.isDate(day, equalTo: today, toGranularity: .weekOfYear) { activity.week = max(0, activity.week - 1) }
        if calendar.isDate(day, equalTo: today, toGranularity: .month) { activity.month = max(0, activity.month - 1) }
        // Today leaves the streak once nothing done is left on it. Earlier
        // days' counts are what the widget reads the streak from.
        if day == today, left == 0 { activity.streak = max(0, activity.streak - 1) }
        snapshot.activity = activity
    }
}
