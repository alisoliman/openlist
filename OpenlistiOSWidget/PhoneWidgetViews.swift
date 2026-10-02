//
//  PhoneWidgetViews.swift
//  OpenlistiOSWidget
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Today

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = OLPalette(scheme)
        Group {
            switch family {
            case .systemMedium: TodayMedium(entry: entry, palette: palette)
            case .accessoryCircular: TodayRing(entry: entry)
            default: TodaySmall(entry: entry, palette: palette)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular { AccessoryWidgetBackground() } else { palette.surface }
        }
        .widgetURL(WidgetLink.today.url)
    }
}

private struct TodaySmall: View {
    let entry: SnapshotEntry
    let palette: OLPalette

    var body: some View {
        let state = entry.state
        let progress = state.phoneTodayProgress
        let next = WidgetNext(state: state)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(shortDay(state.now, calendar: state.calendar))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.todayText)
                Spacer(minLength: 0)
                Image(systemName: "sun.max")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.today)
            }
            Spacer(minLength: 0)
            Text("Today")
                .font(OLSerif.fixed(size: 30))
                .foregroundStyle(palette.ink)
            Text(entry.isPlaceholder ? "Open Openlist" : "\(progress.done) of \(progress.total) done")
                .font(.system(size: 13))
                .foregroundStyle(palette.muted)
            Spacer(minLength: 0)
            WidgetBar(value: progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total), palette: palette)
            if let next {
                let time = Text(next.time).foregroundStyle(palette.accentText).fontWeight(.semibold)
                Text("\(time) \(Text(next.title).foregroundStyle(palette.ink))")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
    }

    private func shortDay(_ date: Date, calendar: Calendar) -> String {
        "\(CompactText.weekday(date, calendar: calendar)) \(calendar.component(.day, from: date))"
    }
}

private struct TodayMedium: View {
    let entry: SnapshotEntry
    let palette: OLPalette

    var body: some View {
        let state = entry.state
        let progress = state.phoneTodayProgress
        let rows = state.phoneTodayRows(limit: 4)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(WidgetFormat.weekdayName(state.now, calendar: state.calendar))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.todayText)
                Text("Today")
                    .font(OLSerif.fixed(size: 28))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                Text("\(progress.total - progress.done) open\n\(state.snapshot.overdueCount) overdue")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if rows.isEmpty {
                    Text(entry.isPlaceholder ? "Open Openlist to see today." : "Today is clear.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.muted)
                        .frame(maxHeight: .infinity)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        TodayWidgetRow(item: item, state: state, palette: palette, separator: index < rows.count - 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// A task in the medium widget: a checkbox that ticks it off in the app, its
/// title, and its time today in the accent.
private struct TodayWidgetRow: View {
    let item: WidgetSnapshot.Item
    let state: WidgetState
    let palette: OLPalette
    let separator: Bool

    var body: some View {
        let check = state.check(for: item)
        let late = item.isOverdue(at: state.now, calendar: state.calendar)
        HStack(spacing: 10) {
            Button(intent: ToggleTaskIntent(taskID: item.id, occurrenceID: item.occurrenceID, completed: check == .open)) {
                WidgetCheckbox(done: check != .open, late: late, palette: palette)
            }
            .buttonStyle(.plain)
            // The circle alone says nothing to VoiceOver; the Mac widget's toggle reads the same.
            .accessibilityLabel(check == .open ? "Complete \(item.title)" : "Reopen \(item.title)")
            text(done: check != .open)
                .font(.system(size: 13))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
        .overlay(alignment: .bottom) {
            if separator { Rectangle().fill(palette.line).frame(height: 1) }
        }
    }

    private func text(done: Bool) -> Text {
        let title = Text(item.title).foregroundStyle(done ? palette.muted : palette.ink).strikethrough(done)
        guard !done, let time = time else { return title }
        return Text("\(title) \(Text(time).foregroundStyle(palette.accentText))")
    }

    /// Its slot today, else the time it's due today.
    private var time: String? {
        let calendar = state.calendar
        if let block = state.snapshot.agenda.first(where: { $0.taskID == item.id && calendar.isDate($0.start, inSameDayAs: state.now) }) {
            return WidgetFormat.clock(block.start, calendar: calendar)
        }
        guard item.includesTime, let due = item.dueDate, calendar.isDate(due, inSameDayAs: state.now) else { return nil }
        return WidgetFormat.clock(due, calendar: calendar)
    }
}

private struct TodayRing: View {
    let entry: SnapshotEntry

    var body: some View {
        let progress = entry.state.phoneTodayProgress
        Gauge(value: Double(progress.done), in: 0...Double(max(1, progress.total))) {
            Text("Today")
        } currentValueLabel: {
            Text("\(progress.done)/\(progress.total)").font(.system(size: 15, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

// MARK: - Inbox

struct InboxWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = OLPalette(scheme)
        let count = entry.state.snapshot.inboxCount
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.infoText)
                Spacer(minLength: 0)
                Image(systemName: "tray")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.info)
            }
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 40, weight: .medium))
                .tracking(-0.8)
                .foregroundStyle(palette.ink)
                .contentTransition(.numericText())
            Text(count == 0 ? "all triaged" : "to triage")
                .font(.system(size: 13))
                .foregroundStyle(palette.muted)
            Spacer(minLength: 0)
            Link(destination: WidgetLink.capture(listID: nil).url) {
                Label("Capture", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(palette.accent, in: .capsule)
            }
        }
        .containerBackground(palette.surface, for: .widget)
        .widgetURL(WidgetLink.inbox.url)
    }
}

// MARK: - Up next

struct UpNextWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let line = WidgetNext(state: entry.state, afterWork: true)
        Group {
            if family == .accessoryInline {
                Text(line.map { "\($0.label) · \($0.time) \($0.title)" } ?? "Nothing else planned")
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.map { "\($0.label) · \($0.time)" } ?? "Up next")
                        .font(.system(size: 12, weight: .semibold))
                        .widgetAccentable()
                    Text(line?.title ?? "Nothing else planned")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        .widgetURL(line?.taskID.map { WidgetLink.task($0).url } ?? WidgetLink.calendar.url)
    }
}

/// What's on, or next, as a widget names it: "10:00 Draft Q3 OKRs".
private struct WidgetNext {
    var label: String
    var time: String
    var title: String
    var taskID: UUID?

    /// The block under way or next; `afterWork` looks past the work in hand
    /// to what comes after it, as the Lock Screen's line beside the Live
    /// Activity does.
    init?(state: WidgetState, afterWork: Bool = false) {
        let upNext = state.upNext
        let calendar = state.calendar
        if afterWork, upNext.isRecording || upNext.phase == .now, let later = upNext.later.first {
            let taskID = state.snapshot.agenda.first { $0.id == later.id }?.taskID
            self.init(label: "Next", time: later.time, title: later.title, taskID: taskID)
        } else if upNext.phase != .none, let start = upNext.start {
            self.init(label: upNext.phase == .next ? "Next" : upNext.phaseLabel,
                      time: WidgetFormat.clock(start, calendar: calendar), title: upNext.title, taskID: upNext.taskID)
        } else {
            return nil
        }
    }

    init(label: String, time: String, title: String, taskID: UUID?) {
        self.label = label
        self.time = time
        self.title = title
        self.taskID = taskID
    }
}

// MARK: - Pieces

/// The design's 4 pt bar.
struct WidgetBar: View {
    let value: Double
    let palette: OLPalette
    var track: Color?

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(track ?? palette.sunken)
                .overlay(alignment: .leading) {
                    Capsule().fill(palette.accent).frame(width: proxy.size.width * min(1, max(0, value)))
                }
        }
        .frame(height: 4)
    }
}

struct WidgetCheckbox: View {
    let done: Bool
    let late: Bool
    let palette: OLPalette

    var body: some View {
        ZStack {
            Circle().fill(done ? palette.success : .clear)
            Circle().strokeBorder(done ? palette.success : late ? palette.danger : palette.lineStrong, lineWidth: 1.6)
            if done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
        .frame(width: 26, height: 30)
        .contentShape(.rect)
    }
}

extension WidgetState {
    /// Done today out of all the iPhone's Today holds: overdue, due, planned
    /// and starred, "2 of 13".
    var phoneTodayProgress: (done: Int, total: Int) {
        let progress = todayProgress
        return (progress.done, progress.total + snapshot.plannedTodayCount)
    }

    /// The medium widget's rows, in the order the iPhone's Today draws them:
    /// one late row to flag the backlog, the left column counting the rest,
    /// then the day's work by its time. A tap's row keeps its place.
    func phoneTodayRows(limit: Int) -> [WidgetSnapshot.Item] {
        let plan = snapshot.todayPlan.isEmpty ? snapshot.todayItems : snapshot.todayPlan
        let rows = plan.filter { !$0.isCompleted || isClosing($0) }
        let late = rows.filter { $0.isOverdue(at: now, calendar: calendar) }
        let rest = rows.filter { !$0.isOverdue(at: now, calendar: calendar) }
        let lateShown = min(late.count, max(1, limit - rest.count))
        return Array((late.prefix(lateShown) + rest).prefix(limit))
    }
}
