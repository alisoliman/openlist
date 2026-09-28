//
//  ActivityScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// Activity (mockup 14), pushed from Today or Settings: the streak and the
/// twelve weeks' count, the heatmap, whose days open what was done on them,
/// and Recent changes, the newest with Undo while this session can take it
/// back.
struct ActivityScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @State private var heatmap: ActivityHeatmap?
    @State private var changes: [ActivityChange] = []
    /// The picked day; nil for today.
    @State private var day: Date?

    var body: some View {
        let navigator = env.navigator
        let now = env.now
        let calendar = env.settings.calendar
        let today = calendar.startOfDay(for: now)
        let selected = day ?? today
        OLScreen(identifier: PhoneRoute.activity.screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .activity)) { navigator.pop() } }
        } content: {
            OLHeader("Activity", sub: heatmap.map(summary))
            if let heatmap {
                ActivityGrid(heatmap: heatmap, today: today, selection: selected, calendar: calendar) { day = $0 == today ? nil : $0 }
                    .padding(.top, OLMetrics.headerGap)
                dayGroup(heatmap: heatmap, day: selected, today: today, now: now)
            }
            if !changes.isEmpty {
                OLGroup("Recent changes") {
                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            changeRow(change, undoable: index == 0 && canUndo(change), now: now)
                                .overlay(alignment: .top) { OLSeparatorLine(separator: index == 0 ? .none : .plain) }
                        }
                    }
                    .olCard()
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in reload() }
        .onChange(of: env.remoteChangeCount) { reload() }
    }

    private func summary(_ heatmap: ActivityHeatmap) -> String {
        let total = "\(heatmap.total) done in 12 weeks"
        return heatmap.streak > 0 ? "\(heatmap.streak)-day streak · \(total)" : total
    }

    // MARK: The picked day

    private func dayGroup(heatmap: ActivityHeatmap, day: Date, today: Date, now: Date) -> some View {
        let calendar = env.settings.calendar
        let entry = heatmap.days.first { calendar.isDate($0.id, inSameDayAs: day) }
        let done = (entry?.completions ?? []).sorted { $0.date > $1.date }
        let title = day == today ? "Today" : OLFormat.eyebrowDate(day, calendar: calendar)
        return OLGroup(title) {
            Text("\(entry?.count ?? 0) done").fontWeight(.medium).contentTransition(.numericText())
        } content: {
            if done.isEmpty {
                Text(day == today ? "Nothing done yet today." : "Nothing done this day.")
                    .font(OLFont.note)
                    .foregroundStyle(OL.muted)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(done.enumerated()), id: \.element.id) { index, item in
                        doneRow(item, separator: index == 0 ? .none : .task(nested: false))
                    }
                }
                .olCard()
            }
        }
        .accessibilityIdentifier("activity.day")
    }

    private func doneRow(_ item: ActivityCompletion, separator: OLSeparator) -> some View {
        let task = item.taskID.flatMap { env.store.block(id: $0) }
        return Button {
            if let task { env.navigator.open(.taskDetail(task.id)) }
        } label: {
            HStack(spacing: 14) {
                OLCheckmark(state: .done)
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(OLFont.rowTitle)
                    .foregroundStyle(OL.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(CompactText.clock(item.date, calendar: env.settings.calendar))
                    .font(OLFont.trailing)
                    .foregroundStyle(OL.muted)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
            .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .disabled(task == nil)
        .accessibilityElement(children: .combine)
    }

    // MARK: Recent changes

    private func changeRow(_ change: ActivityChange, undoable: Bool, now: Date) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(change.text)
                    .font(OLFont.note)
                    .foregroundStyle(OL.ink)
                    .lineLimit(2)
                Text(ActivityChange.ago(change.date, now: now))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if undoable {
                OLChipButton(OLChip("Undo", small: true, tint: OL.accentText)) { env.actions.undoLatest() }
                    .accessibilityLabel("Undo \(change.text)")
                    .accessibilityIdentifier("activity.undo")
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
    }

    /// The newest row is this session's latest step, which it can still undo:
    /// a saved change from the moment of that step, or up to its completion
    /// dwell after, or the work session a start made; never another device's
    /// change since.
    private func canUndo(_ change: ActivityChange) -> Bool {
        guard let latest = env.actions.latest else { return false }
        // Work started: the row of the session that start made.
        guard change.isSaved else { return latest.sessionID.map { $0.uuidString == change.id } ?? false }
        let delay = change.date.timeIntervalSince(latest.at)
        return delay >= -2 && delay <= env.actions.dwell + 5
    }

    private func reload() {
        let now = env.now
        heatmap = try? env.store.activityHeatmap(now: now, calendar: env.settings.calendar, weeks: 12)
        changes = ActivityChange.recent(in: env.store, now: now)
    }
}

/// The heatmap: twelve weeks as columns, a week's days down each. A day with
/// completions shades by how many; today has an accent ring, the picked day
/// an ink one.
private struct ActivityGrid: View {
    let heatmap: ActivityHeatmap
    let today: Date
    let selection: Date
    let calendar: Calendar
    let pick: (Date) -> Void

    var body: some View {
        let days = heatmap.days
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { week in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { row in
                        let index = week * 7 + row
                        if index < days.count { cell(days[index]) } else { upcoming(row) }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .olCard()
        .olFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completions by day")
    }

    /// A day of this week still to come: nothing drawn, "Friday, upcoming".
    private func upcoming(_ row: Int) -> some View {
        let first = heatmap.days.last.map { calendar.dateInterval(of: .weekOfYear, for: $0.id)?.start ?? $0.id }
        let day = first.flatMap { calendar.date(byAdding: .day, value: row, to: $0) }
        return Color.clear
            .frame(height: 23)
            .accessibilityElement()
            .accessibilityLabel(day.map { "\($0.formatted(.dateTime.weekday(.wide))), upcoming" } ?? "Upcoming")
    }

    private func cell(_ day: ActivityHeatmapDay) -> some View {
        let isToday = calendar.isDate(day.id, inSameDayAs: today)
        let isPicked = calendar.isDate(day.id, inSameDayAs: selection)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button { pick(day.id) } label: {
            shape.fill(OL.heat(ActivityBand.level(day.count)))
                .frame(maxWidth: .infinity)
                .frame(height: 23)
                .overlay {
                    if isPicked { shape.strokeBorder(OL.ink, lineWidth: 2) }
                    else if isToday { shape.strokeBorder(OL.accentText, lineWidth: 2) }
                }
                .contentShape(shape)
        }
        .buttonStyle(OLPressStyle(scale: 0.9))
        .accessibilityLabel("\(OLFormat.eyebrowDate(day.id, calendar: calendar)), \(day.count) done")
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// One row of Recent changes: what happened, in a sentence, and when.
struct ActivityChange: Identifiable, Equatable {
    let id: String
    let text: String
    let date: Date
    /// A saved change, rather than work started, which no step undoes.
    var isSaved = true

    /// The newest saved changes, a step's events as one row, with work
    /// started and resumed, which no saved event records.
    @MainActor
    static func recent(in store: Store, now: Date, limit: Int = 8) -> [ActivityChange] {
        var rows: [ActivityChange] = []
        var batches: Set<UUID> = []
        for event in store.recentActivity(limit: 60) {
            if let batch = event.batchID {
                guard batches.insert(batch).inserted else { continue }
            }
            rows.append(ActivityChange(id: event.id.uuidString, text: sentence(for: event), date: event.timestamp))
        }
        let sessions = store.workSessions().sorted { $0.startedAt < $1.startedAt }
        var seen: Set<UUID> = []
        for session in sessions where session.startedAt <= now {
            let resumed = !seen.insert(session.occurrenceID).inserted
            rows.append(ActivityChange(id: session.id.uuidString,
                                       text: "\(resumed ? "Resumed" : "Started") \(session.title)", date: session.startedAt,
                                       isSaved: false))
        }
        return Array(rows.sorted { $0.date > $1.date }.prefix(limit))
    }

    static func sentence(for event: ActivityEvent) -> String {
        let title = event.title.isEmpty ? "Untitled" : event.title
        switch event.kind {
        case .created: return event.change?.copy == nil ? "Added \(title)" : "Duplicated \(title)"
        case .completed: return "Completed \(title)"
        case .reopened: return "Reopened \(title)"
        case .scheduled: return "Scheduled \(title)"
        case .unscheduled: return "Cleared the date of \(title)"
        case .moved:
            if let list = event.change?.after?.listTitle { return "Moved \(title) to \(list)" }
            return "Moved \(title)"
        case .deleted: return "Trashed \(title)"
        case .labeled: return "Labelled \(title)"
        case .starred: return "Starred \(title)"
        case .listCreated: return "Created the list \(title)"
        case .listDeleted: return "Trashed the list \(title)"
        case .noteAdded: return "Added a note to \(title)"
        case .renamed: return "Renamed \(title)"
        case .completionUndone: return "Undid completing \(title)"
        case .restored: return "Restored \(title)"
        }
    }

    /// "just now", "40 min ago", "3 hours ago", "yesterday", "4 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        default: return CompactText.ago(date, now: now)
        }
    }
}
