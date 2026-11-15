//
//  TodayScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// The paper companion's day: progress, the Now card (what's on now and
/// next, meetings and planned work alike, with Fit for the tasks that have no
/// time yet), and quiet cards separating overdue, due, planned, tonight's
/// and starred tasks.
struct TodayScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]

    var body: some View {
        // Ordered outside the clock, so its ticks don't walk every outline again.
        let outline = library.taskRowsInOutlineOrder(blocks: blocks)
        let parents = parentTasks(in: outline)
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            TodayPage(outline: outline, parents: parents, now: env.now)
        }
    }

    /// Task depth already accounts for intervening prose or headings.
    private func parentTasks(in outline: [BlockRow]) -> [UUID: Block] {
        var parents: [UUID: Block] = [:]
        var path: [BlockRow] = []
        for row in outline {
            while let ancestor = path.last, ancestor.depth >= row.depth { path.removeLast() }
            parents[row.id] = path.last?.block
            path.append(row)
        }
        return parents
    }
}

private struct TodayPage: View {
    let outline: [BlockRow]
    let parents: [UUID: Block]
    let now: Date
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The day's meetings, read again only when the calendars reload.
    @State private var meetings = WidgetSnapshotSources.MeetingCache()
    @State private var completionHistory = ActivityHeatmapCache()
    @State private var completionHistoryUnreadable = false

    var body: some View {
        let navigator = env.navigator
        let calendar = env.settings.calendar
        let day = navigator.selectedDay(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let isToday = day == today
        let selection = Binding(get: { day }, set: { navigator.selectDay($0, now: now, calendar: calendar) })
        let work = isToday ? PhoneWork(env: env, now: now) : nil
        let schedule = isToday ? PhoneSchedule.make(env: env, now: now, meetings: meetings) : nil
        let slots = PhoneWork.slots(env.calendar, on: day, calendar: calendar)
        let agenda = TodayAgenda(tasks: outline.map(\.block), on: day, now: now, calendar: calendar,
                                 closing: env.actions.closing, order: .schedule, time: { slots[$0.id] })
        let rows = agenda.nestedRows(in: outline, excluding: work?.task?.id, separateCompleted: true)
        let agendaIDs = Set((agenda.scheduled + agenda.starred).map(\.id))
        let clear = agenda.isClear && work?.task == nil
        let historyDay = completionHistory.heatmap?.days.first { $0.id == day }
        let additional = agenda.additionalCompletions(in: historyDay)
        let completedCount = rows.doneToday.count + additional.count
        let historyWindow = HistoryWindow(today: today, calendar: calendar,
                                          weeks: max(12, -CompactText.dayOffset(from: now, to: day, calendar: calendar) / 7 + 2))
        let historyUnreadable = day <= today && completionHistoryUnreadable
        let scrolls = dynamicTypeSize.isAccessibilitySize || !clear || schedule?.hasRest == true
            || completedCount > 0 || historyUnreadable
        OLScreen(identifier: PhoneRoute.today.screenIdentifier, scrolls: scrolls) {
            TodayProgressHeader(title: dayTitle(day, calendar: calendar),
                                done: agenda.progress.done + additional.count, total: agenda.progress.total + additional.count) {
                OLIconButton("calendar", label: "Timeline", kind: .bare) { navigator.openTimeline(on: navigator.timelineDay) }
                    .accessibilityIdentifier("today.timeline")
                OLIconButton("gearshape", label: "Settings", kind: .bare, iconSize: 22) { navigator.open(.settings) }
                    .accessibilityIdentifier("today.settings")
            }
            OLDayStepper(selection: selection, today: now, calendar: calendar,
                         identifierPrefix: "today", hasHaptics: dynamicTypeSize.isAccessibilitySize)
                .padding(.top, 12)
            if !dynamicTypeSize.isAccessibilitySize {
                OLWeekStrip(days: OLWeekStrip.week(containing: day, calendar: calendar), selection: selection,
                            today: now, calendar: calendar)
                    .padding(.top, 4)
            }
            if let work, let schedule {
                // Today's meetings can still be shown on a clear day.
                if !clear || schedule.hasRest {
                    TodayScheduleCard(schedule: schedule, work: work, now: now,
                                      toPlan: PhoneSchedule.unplaced(agenda.scheduled, slotted: { slots[$0] != nil },
                                                                     workID: work.task?.id, closing: env.actions.closing),
                                      showsNotes: !clear, folds: true, cardShadow: .softCard)
                        .padding(.top, OLMetrics.headerGap)
                }
            }
            if clear && (isToday || completedCount == 0) {
                if env.awaitsFirstImport(library) {
                    OLLoadingState("Getting your lists from iCloud…")
                        .frame(maxHeight: .infinity)
                } else if isToday {
                    let first = library.tasks.isEmpty
                    OLEmptyState(symbol: "sun.max", title: "Today is clear", message: "Nothing is overdue, due, planned or starred.",
                                 actionTitle: first ? "Add a task" : "Look at tomorrow") {
                        if first { navigator.open(.capture(CaptureRequest(dueToday: true))) }
                        else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) { selection.wrappedValue = tomorrow }
                    }
                    .padding(.top, scrolls ? OLMetrics.headerGap : 0)
                    .frame(maxHeight: .infinity)
                } else {
                    OLEmptyState(symbol: "calendar", title: "No tasks for this day")
                        .padding(.top, scrolls ? OLMetrics.headerGap : 0)
                        .frame(maxHeight: .infinity)
                }
            }
            taskGroup("Overdue", rows: rows.overdue, agendaIDs: agendaIDs, slots: slots, day: day)
            taskGroup(isToday ? "Due today" : "Due", rows: rows.due, agendaIDs: agendaIDs, slots: slots,
                      day: day, showsDueToday: !isToday)
            taskGroup("Planned", rows: rows.planned, agendaIDs: agendaIDs, slots: slots, day: day)
            taskGroup(isToday ? "Tonight" : "Evening", rows: rows.tonight, agendaIDs: agendaIDs, slots: slots, day: day)
            taskGroup("Starred", rows: rows.starred, agendaIDs: agendaIDs, slots: slots, day: day)
            if completedCount > 0 {
                TodayCompletedSection(rows: rows.doneToday, additional: additional, day: day, isToday: isToday,
                                      subtitle: subtitle(for:visibleIDs:))
                    .id(day)
            }
            if historyUnreadable {
                OLLoadFailure("Saved activity could not be read.") { reloadHistory(historyWindow) }
                    .padding(.top, OLMetrics.groupGap)
            }
            if isToday && !clear {
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
        .task(id: historyWindow) { reloadHistory(historyWindow) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in reloadHistory(historyWindow) }
        .onChange(of: env.remoteChangeCount) { reloadHistory(historyWindow) }
        .onChange(of: completionHistory.heatmap?.nextCompletionAt.map { now >= $0 } == true) { _, available in
            if available { reloadHistory(historyWindow) }
        }
    }

    private struct HistoryWindow: Equatable {
        let today: Date
        let calendar: Calendar
        let weeks: Int
    }

    private func reloadHistory(_ window: HistoryWindow) {
        do {
            _ = try completionHistory.refresh(store: env.store, now: now, calendar: window.calendar, weeks: window.weeks)
            completionHistoryUnreadable = false
        } catch {
            completionHistory = ActivityHeatmapCache()
            completionHistoryUnreadable = true
        }
    }

    private func dayTitle(_ day: Date, calendar: Calendar) -> String {
        switch CompactText.dayOffset(from: now, to: day, calendar: calendar) {
        case -1: "Yesterday"
        case 0: "Today"
        case 1: "Tomorrow"
        default: calendar.weekdaySymbols[calendar.component(.weekday, from: day) - 1]
        }
    }

    @ViewBuilder private func taskGroup(_ title: String, rows: [BlockRow], agendaIDs: Set<UUID>, slots: [UUID: Date],
                                        day: Date, showsDueToday: Bool = true) -> some View {
        if !rows.isEmpty {
            let visibleIDs = Set(rows.lazy.map(\.id))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text(title).font(OLFont.groupHeader).accessibilityAddTraits(.isHeader)
                    Text("\(rows.count { agendaIDs.contains($0.id) })").font(.caption.monospacedDigit())
                }
                .foregroundStyle(OL.muted)
                .padding(.horizontal, 4)
                OLCardRows(rows, depth: \.depth, shadow: .softCard) { row, separator in
                    let task = row.block
                    PhoneTaskRow(task: task, context: .today, depth: row.depth,
                                 subtitle: subtitle(for: task, visibleIDs: visibleIDs),
                                 separator: separator, slot: slots[task.id], agendaDay: day,
                                 showsDueToday: showsDueToday,
                                 subtasks: task.isStarred ? progress(of: task) : nil)
                }
            }
            .padding(.top, OLMetrics.groupGap)
            // Moved as one when the page shifts, as the schedule folding
            // does, so the due menus drawn over the rows move with them.
            .geometryGroup()
        }
    }

    private func subtitle(for task: Block, visibleIDs: Set<UUID>) -> String? {
        if let parent = parents[task.id], !visibleIDs.contains(parent.id) {
            return "Subtask of \(parent.displayTitle)"
        }
        return library.list(task.listID)?.displayTitle
    }

    private func progress(of task: Block) -> (done: Int, total: Int)? {
        let subtasks = library.subtasks(of: task)
        guard !subtasks.isEmpty else { return nil }
        return (subtasks.count(where: \.isCompleted), subtasks.count)
    }
}
