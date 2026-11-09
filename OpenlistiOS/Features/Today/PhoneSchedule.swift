//
//  PhoneSchedule.swift
//  OpenlistiOS
//

import Foundation
import UIKit

/// The day's meetings and planned sessions as the phone reads them, through
/// the Mac's model (`TodaySchedule`): the blocks the calendar draws and the
/// calendars' busy time, so Today, the Timeline and the Mac's Today agree on
/// what's on now and what comes next. It reads; it never plans.
@MainActor
enum PhoneSchedule {
    /// `day`'s schedule, today's unless given, read as the calendar draws it:
    /// a session's title is its task's, and one ticked and still settling is
    /// done. `meetings` keeps the calendars' busy time between reloads.
    static func make(env: PhoneEnvironment, now: Date, day: Date? = nil,
                     meetings: WidgetSnapshotSources.MeetingCache? = nil) -> TodaySchedule {
        let calendar = env.settings.calendar
        let start = calendar.startOfDay(for: day ?? now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let source = env.calendar.externalCalendars
        let span = DateInterval(start: start, end: end)
        let busy = meetings?.busyTimes(in: span, from: source) ?? source.busyTimes(in: span)
        let store = env.store
        let actions = env.actions
        return TodaySchedule(blocks: env.calendar.visibleBlocks, busy: busy, now: now, day: day, calendar: calendar,
                             title: { store.block(id: $0.taskID)?.displayTitle ?? $0.titleSnapshot ?? "Task" },
                             isDone: { block in
                                 block.isCompleted || store.block(id: block.taskID)?.isCompleted == true
                                     || actions.isClosing(block.taskID)
                             })
    }

    /// Whether the schedule can show meetings.
    enum Connection: Equatable {
        /// Calendars allowed, or a review session's fixture standing in for them.
        case connected
        /// None connected yet: Connect asks for access.
        case notConnected
        /// Connected once, with access since turned off in Settings.
        case unavailable
    }

    static func connection(_ source: ExternalCalendarSource) -> Connection {
        if source.isFixture || source.isAuthorized { return .connected }
        return source.isConnected ? .unavailable : .notConnected
    }

    /// Today's tasks with no time yet, as the Mac's Today counts them: late,
    /// due or planned for today, with no slot on the calendar today and no
    /// time of day, and not the work in hand or a tick still settling. Fit
    /// gives each the next free slot.
    static func unplaced(_ scheduled: [Block], slotted: (UUID) -> Bool, workID: UUID?, closing: Set<UUID>) -> [Block] {
        scheduled.filter {
            !$0.isCompleted && !$0.includesTime && !slotted($0.id) && $0.id != workID && !closing.contains($0.id)
        }
    }

    /// Connects this iPhone's calendars as Settings › Calendar access does:
    /// asks for access, or, where it was turned down, opens Openlist's page in
    /// Settings, where it can be allowed.
    static func connect(_ env: PhoneEnvironment) {
        let source = env.calendar.externalCalendars
        Task {
            await source.requestAccess()
            if source.isAuthorized {
                env.calendar.refreshCalendars(now: env.now)
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
    }

    /// The Calendar app at `date`, for a meeting's Open in Calendar.
    static func calendarApp(at date: Date) -> URL? {
        URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))")
    }
}

/// Today's Now card as lines: what's under way, the work in hand first, then
/// the first thing still to start today, meetings included. At most two
/// things now, as the Mac's schedule shows them, and one next.
@MainActor
struct TodayNowNext {
    struct Line: Identifiable {
        enum Kind: Equatable {
            /// The work in hand, which the card's button starts, resumes or
            /// goes back to.
            case work(PhoneWork.State)
            case session
            case meeting
        }

        let id: String
        let role: OLNowRole
        let kind: Kind
        let title: String
        /// "Working · 50 min left", "Until 15:00", "14:00 · in 3h 20m".
        let time: String
        /// A meeting's place, or a session's list.
        let place: String?
        let taskID: UUID?
        /// A session's list, whose colour marks it.
        let listID: UUID?
        let meeting: FixedBusyTime?

        /// The time and place as one line: "14:00 · in 3h 20m · Studio".
        var detail: String { [time, place].compactMap(\.self).joined(separator: " · ") }
    }

    let lines: [Line]
    /// Nothing on the calendar today and no work in hand.
    let isEmpty: Bool

    /// What the card says with no line to show.
    var emptyText: String? {
        guard lines.isEmpty else { return nil }
        return isEmpty ? "Nothing scheduled today." : "Nothing else scheduled today."
    }

    /// - Parameters:
    ///   - task: a session's task, for its list.
    ///   - list: a list's title.
    init(schedule: TodaySchedule, work: PhoneWork, now: Date, calendar: Calendar,
         task: (UUID) -> Block?, list: (UUID?) -> String?) {
        func clock(_ date: Date) -> String { CompactText.clock(date, calendar: calendar) }
        func session(_ item: TodaySchedule.Item, role: OLNowRole) -> Line {
            let listID = item.taskID.flatMap(task)?.listID
            let time = role == .next
                ? "\(clock(item.start)) · in \(OLFormat.span(OLFormat.minutes(from: now, to: item.start)))"
                : "Until \(clock(item.end))"
            let place = item.kind == .meeting ? item.meeting?.location : list(listID)
            return Line(id: item.id, role: role, kind: item.kind == .meeting ? .meeting : .session, title: item.title,
                        time: time, place: place, taskID: item.taskID, listID: item.kind == .meeting ? nil : listID,
                        meeting: item.meeting)
        }

        var current: [Line] = []
        if let task = work.task {
            // The work in hand leads, whether its block is on now or not:
            // paused work can sit past the end of its slot.
            let time = switch work.state {
            case .working: "Working · \(work.leftText)"
            case .paused: "Paused · \(work.leftText)"
            case .planned: work.end.map { "Until \(clock($0))" } ?? work.leftText
            }
            current.append(Line(id: "work-\(task.id)", role: .now, kind: .work(work.state), title: task.displayTitle,
                            time: time, place: list(task.listID), taskID: task.id, listID: task.listID, meeting: nil))
        }
        for item in schedule.current where current.count < 2 {
            if let id = item.taskID, id == work.task?.id { continue }
            current.append(session(item, role: current.isEmpty ? .now : .alsoNow))
        }
        var lines = current
        // The schedule's next, passing over a later slot of the work in hand.
        let workID = work.task?.id
        func isWork(_ item: TodaySchedule.Item) -> Bool { item.taskID != nil && item.taskID == workID }
        let next = schedule.next.flatMap { isWork($0) ? nil : $0 } ?? schedule.items.first {
            !$0.isDone && !$0.isActive && $0.start > now && !isWork($0)
        }
        if let next { lines.append(session(next, role: .next)) }
        self.lines = lines
        isEmpty = schedule.isEmpty && work.task == nil
    }
}
