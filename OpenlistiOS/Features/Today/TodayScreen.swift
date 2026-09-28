//
//  TodayScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// Today (mockups 01, 02): the work on now, then the day's overdue, due and
/// planned tasks in one card by the time they're placed or due, Starred, and
/// how many are done, which opens Activity. When nothing is left: Today is
/// clear, and a look at tomorrow.
struct TodayScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    /// Every document block, for the order the lists show their tasks in.
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]

    var body: some View {
        // The design's 20 s clock: late days, times left and the date move on.
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            TodayPage(tasks: library.tasksInOutlineOrder(blocks: blocks), now: env.now)
        }
    }
}

private struct TodayPage: View {
    let tasks: [Block]
    let now: Date
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let navigator = env.navigator
        let calendar = env.settings.calendar
        let work = PhoneWork(env: env, now: now)
        let slots = PhoneWork.slots(env.calendar, on: now, calendar: calendar)
        let agenda = TodayAgenda(tasks: tasks, closing: env.actions.closing, now: now, calendar: calendar,
                                 order: .schedule, time: { slots[$0.id] })
        let nowID = work.task?.id
        let scheduled = agenda.scheduled.filter { $0.id != nowID }
        let starred = agenda.starred.filter { $0.id != nowID }
        OLScreen(identifier: PhoneRoute.today.screenIdentifier, scrolls: !(agenda.isClear && work.task == nil)) {
            OLTopBar {
                OLEyebrow(OLFormat.eyebrowDate(now, calendar: calendar))
            } trailing: {
                OLViewToggle(selection: .list, from: navigator.todaySwitchedFrom == .timeline ? .calendar : nil,
                             calendarIdentifier: "today.timeline", arrived: { _ = navigator.takeTodaySwitch() }) { _ in
                    navigator.openTimeline(on: nil)
                }
            }
        } content: {
            OLHeader("Today")
            if agenda.isClear && work.task == nil {
                OLEmptyState(symbol: "sun.max", title: "Today is clear", message: clearMessage(done: agenda.doneToday.count),
                             actionTitle: "Look at tomorrow") {
                    navigator.openTimeline(on: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
                }
                .frame(maxHeight: .infinity)
            } else {
                if let card = work.card {
                    OLNowCard(eyebrow: card.eyebrow, title: card.title, detail: card.detail, state: card.state,
                              open: { navigator.open(.working) }, play: { work.play(env) })
                        .padding(.top, OLMetrics.headerGap)
                }
                if !scheduled.isEmpty {
                    rows(scheduled, slots: slots)
                        .padding(.top, work.card == nil ? OLMetrics.headerGap : OLMetrics.cardGap)
                }
                if !starred.isEmpty {
                    OLGroup("Starred") { rows(starred, slots: slots) }
                }
                if !agenda.doneToday.isEmpty {
                    OLLinkRow("done today", count: agenda.doneToday.count) { navigator.open(.activity) }
                        .accessibilityIdentifier("today.done")
                }
            }
        }
    }

    private func rows(_ tasks: [Block], slots: [UUID: Date]) -> some View {
        OLCardRows(tasks) { task, separator in
            PhoneTaskRow(task: task, context: .today, separator: separator, slot: slots[task.id],
                         subtasks: task.isStarred ? progress(of: task) : nil)
        }
    }

    /// A starred task's subtasks: "1 of 3".
    private func progress(of task: Block) -> (done: Int, total: Int)? {
        let subtasks = library.subtasks(of: task)
        guard !subtasks.isEmpty else { return nil }
        return (subtasks.count(where: \.isCompleted), subtasks.count)
    }

    private func clearMessage(done: Int) -> String {
        let finished = done == 0 ? "" : "\(done) finished today. "
        return finished + "Nothing is overdue, due, planned or starred."
    }
}
