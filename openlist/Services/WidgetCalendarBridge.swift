//
//  WidgetCalendarBridge.swift
//  openlist
//

import AppKit
import Foundation

extension WidgetSnapshotSources {
    /// Reads settings, the day's plan and the work timer the way the app's own
    /// screens do, so a widget shows the same day as the window.
    static func live(calendar coordinator: CalendarCoordinator, settings: AppSettings,
                     libraryID: UUID?) -> WidgetSnapshotSources {
        var sources = WidgetSnapshotSources()
        sources.libraryID = libraryID
        sources.accentHex = { settings.accent.hex }
        sources.serifTitles = { settings.serifTitles }
        sources.calendar = { settings.calendar }
        sources.agenda = { interval in agenda(in: interval, coordinator: coordinator) }
        sources.work = { now in work(at: now, coordinator: coordinator, calendar: settings.calendar) }
        sources.isAppActive = { NSApplication.shared.isActive }
        return sources
    }

    /// Meetings and task blocks overlapping `interval`, filtered as the
    /// Calendar screen draws them: events of 20 hours or more are all-day
    /// busy time rather than meetings.
    static func agenda(in interval: DateInterval, coordinator: CalendarCoordinator) -> [WidgetSnapshot.AgendaEvent] {
        let store = coordinator.store
        let meetings = coordinator.externalCalendars.busyTimes.filter {
            $0.end > interval.start && $0.start < interval.end && $0.end.timeIntervalSince($0.start) < 20 * 3600
        }.map {
            WidgetSnapshot.AgendaEvent(id: $0.id, kind: .meeting, title: $0.title, start: $0.start, end: $0.end)
        }

        var tasks: [UUID: Block] = [:]
        var lists: [UUID: TaskList] = [:]
        let blocks = coordinator.visibleBlocks.filter { $0.end > interval.start && $0.start < interval.end }
            .map { block -> WidgetSnapshot.AgendaEvent in
                if tasks[block.taskID] == nil { tasks[block.taskID] = store.block(id: block.taskID) }
                let task = tasks[block.taskID]
                if let listID = task?.listID, lists[listID] == nil { lists[listID] = store.list(id: listID) }
                let list = task?.listID.flatMap { lists[$0] }
                return WidgetSnapshot.AgendaEvent(
                    id: block.id,
                    kind: .task,
                    title: task?.displayTitle ?? block.titleSnapshot ?? "Task",
                    start: block.start,
                    end: block.end,
                    taskID: block.taskID,
                    occurrenceID: block.occurrenceID,
                    listName: list?.displayTitle ?? "",
                    listIcon: list?.glyph ?? "",
                    accentHex: list?.displayAccentHex,
                    isCompleted: block.isCompleted || task?.isCompleted == true,
                    isActive: block.isActive
                )
            }
        return meetings + blocks
    }

    /// The work the toolbar timer shows: the running session, or paused work
    /// that can still resume.
    static func work(at now: Date, coordinator: CalendarCoordinator, calendar: Calendar = .current) -> WidgetSnapshot.Work? {
        let store = coordinator.store
        if let session = coordinator.activeSession {
            guard let task = store.block(id: session.taskID) else { return nil }
            // Earlier segments are closed, so their total holds still while this one runs.
            let prior = store.workSessions(taskID: task.id)
                .filter { $0.id != session.id && $0.occurrenceID == session.occurrenceID && $0.endedAt != nil }
                .reduce(0) { $0 + coordinator.recordedMinutes(for: $1, now: now) * 60 }
            // Starting replans the running block from the moment of Start; the
            // slot it was started in is the one the plan showed.
            let started = session.plannedIntervals.first { $0.start <= session.startedAt && session.startedAt < $0.end }
            let running = coordinator.plan.blocks.first { $0.isActive && $0.occurrenceID == session.occurrenceID }
            return mirror(task, state: .working, segmentStartedAt: session.startedAt, priorSeconds: prior,
                          block: started.map { ($0.start, $0.end) } ?? running.map { ($0.start, $0.end) },
                          coordinator: coordinator)
        }
        guard let task = coordinator.resumableTask else { return nil }
        // Paused work shows the slot it was interrupted in, as the running
        // header did. Pausing replans the rest, often to another day, and a
        // block from another day would read as a time today, so whichever
        // is shown must be today's: the interrupted slot, or failing that
        // the next block, or none.
        let interrupted = store.workSessions(taskID: task.id)
            .filter { $0.occurrenceID == task.occurrenceID && $0.endedAt != nil }
            .max { $0.startedAt < $1.startedAt }
            .flatMap { session in session.plannedIntervals.first { $0.start <= session.startedAt && session.startedAt < $0.end } }
            .map { (start: $0.start, end: $0.end) }
        let next = coordinator.plannedWork(WorkTaskReference(task), now: now).map { (start: $0.start, end: $0.end) }
        let block = [interrupted, next].lazy.compactMap { $0 }.first { calendar.isDate($0.start, inSameDayAs: now) }
        return mirror(task, state: .paused, segmentStartedAt: nil,
                      priorSeconds: coordinator.trackedMinutes(for: task, now: now) * 60,
                      block: block, coordinator: coordinator)
    }

    private static func mirror(_ task: Block, state: WidgetSnapshot.Work.State, segmentStartedAt: Date?,
                               priorSeconds: Double, block: (start: Date, end: Date)?,
                               coordinator: CalendarCoordinator) -> WidgetSnapshot.Work {
        let list = coordinator.store.list(id: task.listID)
        // The toolbar timer's estimate, so its bar and the widget's fill alike.
        let defaultEstimate = max(5, Int(coordinator.preferences.defaultEstimateMinutes))
        let estimate = max(5, task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate)
        return WidgetSnapshot.Work(
            state: state,
            taskID: task.id,
            occurrenceID: task.occurrenceID,
            title: task.displayTitle,
            listName: list?.displayTitle ?? "",
            listIcon: list?.glyph ?? "",
            accentHex: list?.displayAccentHex ?? ListAccent.graphite.hex,
            segmentStartedAt: segmentStartedAt,
            priorSeconds: priorSeconds,
            estimateMinutes: Double(estimate),
            blockStart: block?.start,
            blockEnd: block?.end
        )
    }
}
