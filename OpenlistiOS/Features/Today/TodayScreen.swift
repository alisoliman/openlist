//
//  TodayScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// The paper companion's day: progress, the current work, and quiet cards
/// separating overdue, due, planned and starred tasks.
struct TodayScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]

    var body: some View {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let navigator = env.navigator
        let calendar = env.settings.calendar
        let work = PhoneWork(env: env, now: now)
        let slots = PhoneWork.slots(env.calendar, on: now, calendar: calendar)
        let agenda = TodayAgenda(tasks: tasks, closing: env.actions.closing, now: now, calendar: calendar,
                                 order: .schedule, time: { slots[$0.id] })
        OLScreen(identifier: PhoneRoute.today.screenIdentifier, scrolls: !(agenda.isClear && work.task == nil)) {
            OLTopBar {
                if !dynamicTypeSize.isAccessibilitySize {
                    OLEyebrow(OLFormat.eyebrowDate(now, calendar: calendar))
                }
            } trailing: {
                OLIconButton("calendar", label: "Timeline", kind: .bare) { navigator.openTimeline(on: nil) }
                    .accessibilityIdentifier("today.timeline")
                OLIconButton("gearshape", label: "Settings", kind: .plain) { navigator.open(.settings) }
                    .accessibilityIdentifier("today.settings")
            }
        } content: {
            if dynamicTypeSize.isAccessibilitySize {
                OLEyebrow(OLFormat.eyebrowDate(now, calendar: calendar))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TodayProgressHeader(done: agenda.progress.done, total: agenda.progress.total)
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
                taskGroup("Overdue", symbol: "exclamationmark.circle.fill", color: OL.danger,
                          tasks: agenda.overdue, slots: slots, nowID: work.task?.id)
                taskGroup("Due today", symbol: "sun.max.fill", color: OL.today,
                          tasks: agenda.due, slots: slots, nowID: work.task?.id)
                taskGroup("Planned", symbol: "calendar", color: OL.ink,
                          tasks: agenda.planned, slots: slots, nowID: work.task?.id)
                taskGroup("Starred", symbol: "star.fill", color: OL.today,
                          tasks: agenda.starred, slots: slots, nowID: work.task?.id)
                if !agenda.doneToday.isEmpty {
                    OLLinkRow("Completed today", count: agenda.doneToday.count) { navigator.open(.activity) }
                        .accessibilityIdentifier("today.done")
                }
                Button { navigator.open(.capture(CaptureRequest(dueToday: true))) } label: {
                    Label("Add task", systemImage: "plus")
                        .font(OLFont.rowTitle)
                        .foregroundStyle(OL.muted)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(OLRowPressStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("today.add")
            }
        }
    }

    @ViewBuilder private func taskGroup(_ title: String, symbol: String, color: Color,
                                        tasks: [Block], slots: [UUID: Date], nowID: UUID?) -> some View {
        let visible = tasks.filter { $0.id != nowID }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
                    Text(title).font(OLFont.groupHeader).accessibilityAddTraits(.isHeader)
                    Text("\(visible.count)").font(OLFont.meta).foregroundStyle(OL.muted)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(OL.muted)
                .padding(.horizontal, 4)
                OLCardRows(visible) { task, separator in
                    PhoneTaskRow(task: task, context: .today,
                                 subtitle: library.list(task.listID)?.displayTitle,
                                 separator: separator, slot: slots[task.id],
                                 subtasks: task.isStarred ? progress(of: task) : nil)
                }
            }
            .padding(.top, OLMetrics.groupGap)
        }
    }

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
