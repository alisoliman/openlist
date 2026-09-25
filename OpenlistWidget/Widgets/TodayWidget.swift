//
//  TodayWidget.swift
//  OpenlistWidget
//

import AppKit
import SwiftUI
import WidgetKit

/// Overdue and due-today work, ticked off in place.
struct TodayWidget: Widget {
    static let kind = WidgetKind.today

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                TodayWidgetView(entry: entry, family: family, style: style)
            }
            .widgetURL(WidgetLink.today.url)
        }
        .configurationDisplayName("Today")
        .description("What’s due and overdue. Tick tasks off without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if entry.isPlaceholder {
            OpenAppPrompt()
        } else {
            let today = TodayDigest(state: entry.state)
            switch family {
            case .systemSmall: TodaySmall(today: today)
            case .systemMedium: TodayMedium(today: today)
            default: TodayLarge(today: today)
            }
        }
    }
}

// MARK: - Families

/// A compact header over two rows whose titles wrap.
private struct TodaySmall: View {
    let today: TodayDigest
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayHeader(today: today) {
                Text("Today")
                    .lineLimit(1)
                    .textStyle(13, .bold, lineHeight: 1)
            }
            Group {
                if today.isClear {
                    TodayClear(today: today, titleSize: 20)
                } else {
                    // Two-line titles leave no room for "+N more" at the
                    // design's spacing, so tighten before giving it up.
                    ViewThatFits(in: .vertical) {
                        TodayRows(today: today, limit: 2, spacing: 8, layout: .compact)
                        TodayRows(today: today, limit: 2, spacing: 6, layout: .compact)
                        TodayRows(today: today, limit: 2, spacing: 8, showsMore: false, layout: .compact)
                        TodayRows(today: today, limit: 1, spacing: 8, layout: .compact)
                    }
                }
            }
            .padding(.top, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The date and the day's progress beside the first few rows.
private struct TodayMedium: View {
    let today: TodayDigest
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            dateColumn
                .frame(width: 98, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            Hairline(.vertical)
                .padding(.horizontal, 14)
            Group {
                if today.isClear {
                    TodayClear(today: today, titleSize: 22)
                } else {
                    ViewThatFits(in: .vertical) {
                        TodayRows(today: today, limit: 3)
                        TodayRows(today: today, limit: 3, showsMore: false)
                        TodayRows(today: today, limit: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CapsLabel(WidgetFormat.weekdayName(today.now, calendar: today.calendar), color: style.orange)
                Text(today.dayNumber)
                    .lineLimit(1)
                    .displayStyle(50, lineHeight: 0.9, style: style)
                    .padding(.top, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetFormat.weekdayName(today.now, calendar: today.calendar) + " " + today.dayNumber)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ProgressRing(fraction: today.fraction, size: 26, lineWidth: 3.25)
                    .invalidatableContent()
                VStack(alignment: .leading, spacing: 4) {
                    // The column leaves the label about 64 points, which
                    // "14 of 165 done" overruns, so a three-digit total
                    // drops the "done".
                    ViewThatFits(in: .horizontal) {
                        progressLine(progressText)
                        progressLine(compactProgressText)
                            .minimumScaleFactor(0.8)
                    }
                    if today.late > 0 {
                        LateCount(count: today.late)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(today.progressDescription)
        }
    }

    private func progressLine(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .contentTransition(.numericText(value: Double(today.done)))
            .foregroundStyle(style.ink)
            .lineLimit(1)
            .textStyle(11, .semibold, lineHeight: 1)
            .invalidatableContent()
    }

    /// "2 of 9 done"; a day with nothing due at all has no fraction to show.
    private var progressText: LocalizedStringKey {
        today.total > 0 ? "\(today.done) of \(today.total) done" : "None due"
    }

    /// "14 of 165", when "done" no longer fits beside the ring.
    private var compactProgressText: LocalizedStringKey {
        today.total > 0 ? "\(today.done) of \(today.total)" : "None due"
    }
}

/// The serif header, late work and the rest of today in sections, and a
/// footer for adding a task.
private struct TodayLarge: View {
    let today: TodayDigest
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayHeader(today: today) {
                Text("Today")
                    .lineLimit(1)
                    .displayStyle(23, lineHeight: 1, style: style)
            }
            Group {
                if today.isClear {
                    TodayClear(today: today, titleSize: 26)
                } else {
                    ViewThatFits(in: .vertical) {
                        TodayRows(today: today, limit: 5, showsSections: true)
                        TodayRows(today: today, limit: 4, showsSections: true)
                        TodayRows(today: today, limit: 3, showsSections: true)
                    }
                }
            }
            .padding(.top, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Hairline()
            HStack(spacing: 8) {
                // As New task on the app's Today screen: an undated task is
                // due today, so it lands in this widget.
                ChipLink("New task", link: .captureToday)
                Spacer(minLength: 0)
                Text(doneText)
                    .contentTransition(.numericText(value: Double(today.done)))
                    .foregroundStyle(style.sub)
                    .lineLimit(1)
                    .textStyle(10.5, .medium, lineHeight: 1)
                    .invalidatableContent()
            }
        }
    }

    private var doneText: LocalizedStringKey {
        today.done > 0 ? "\(today.done) done today" : "Nothing done yet"
    }
}

// MARK: - Parts

/// Sun, title, the late count and the progress ring: the small and large
/// families' first line.
private struct TodayHeader<Title: View>: View {
    let today: TodayDigest
    private let title: Title
    @Environment(\.widgetStyle) private var style

    init(today: TodayDigest, @ViewBuilder title: () -> Title) {
        self.today = today
        self.title = title()
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(style.orange)
                    .widgetAccentable()
                    .frame(width: 14, height: 14)
                title
            }
            // The title keeps its width; the late count gives way first.
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today")
            .accessibilityAddTraits(.isHeader)
            // The design has 6 points either side of its spacer. One is
            // enough, and it leaves room for "128 late" on a 164-point widget.
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                if today.late > 0 {
                    LateCount(count: today.late)
                }
                ProgressRing(fraction: today.fraction)
                    .invalidatableContent()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(today.progressDescription)
        }
    }
}

/// "3 late", in red, or just "1,280" where the word does not fit. VoiceOver
/// reads the full count from the progress description either way.
private struct LateCount: View {
    let count: Int
    @Environment(\.widgetStyle) private var style

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text("\(count) late").fixedSize()
            Text(count, format: .number).fixedSize()
        }
        .contentTransition(.numericText(value: Double(count)))
        .foregroundStyle(style.red)
        .lineLimit(1)
        .textStyle(10.5, .semibold, lineHeight: 1)
        .invalidatableContent()
    }
}

/// The first `limit` rows, late work first, with a count of the rest.
private struct TodayRows: View {
    let today: TodayDigest
    let limit: Int
    var spacing: CGFloat = 7
    /// Splits the rows under OVERDUE and DUE TODAY labels (the large family).
    var showsSections = false
    var showsMore = true
    var layout = TaskRow.Layout.standard

    var body: some View {
        let shown = Array(today.rows.prefix(limit))
        let hidden = today.hiddenCount(showing: shown.count)
        VStack(alignment: .leading, spacing: spacing) {
            if showsSections {
                let late = shown.filter(today.isOverdue)
                let rest = shown.filter { !today.isOverdue($0) }
                if !late.isEmpty {
                    SectionLabel(title: "Overdue", isLate: true)
                        .padding(.top, 2)
                    rows(late)
                }
                if !rest.isEmpty {
                    SectionLabel(title: "Due today", isLate: false)
                        .padding(.top, late.isEmpty ? 2 : 7)
                    rows(rest)
                }
            } else {
                rows(shown)
            }
            if showsMore, hidden > 0 {
                MoreLabel(count: hidden)
                    .accessibilityLabel("\(hidden) more due")
            }
        }
    }

    private func rows(_ items: [WidgetSnapshot.Item]) -> some View {
        ForEach(items, id: \.occurrenceID) { item in
            TaskRow(item: item, state: today.state, layout: layout)
        }
    }
}

/// "OVERDUE" in red, "DUE TODAY" in the quiet caps colour.
private struct SectionLabel: View {
    let title: String
    let isLate: Bool
    @Environment(\.widgetStyle) private var style

    var body: some View {
        CapsLabel(title, color: isLate ? style.red : style.faint, size: 9.5)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Nothing due or overdue: a quiet serif line where the rows would be, under
/// the green tick the rows' own done state uses.
private struct TodayClear: View {
    let today: TodayDigest
    let titleSize: CGFloat
    @Environment(\.widgetStyle) private var style

    var body: some View {
        if today.state.isOutdated {
            // Days without the app: nothing known is due, which is not the
            // same as a clear day.
            OpenAppPrompt(isOutdated: true)
        } else {
            clear
        }
    }

    private var clear: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(style.onAcc)
                .frame(width: 22, height: 22)
                .background(Circle().fill(style.green).widgetAccentable())
                .padding(.bottom, 2)
            Text("All clear")
                .lineLimit(1)
                .displayStyle(titleSize, lineHeight: 1, style: style)
            Text(message)
                .foregroundStyle(style.sub)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textStyle(11, .medium, lineHeight: 1.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var message: LocalizedStringKey {
        today.done > 0 ? "Nothing left for today." : "Nothing due or overdue."
    }
}

// MARK: - Data

/// What every family reads from the entry's state, worked out once.
private nonisolated struct TodayDigest {
    let state: WidgetState
    /// Late work first, then the rest of today, each in the app's order. The
    /// app sorts by due date, which puts an untimed task due today ahead of
    /// one whose time has already passed; the widget groups by lateness.
    let rows: [WidgetSnapshot.Item]
    let late: Int
    let done: Int
    /// Done plus everything still due by today.
    let total: Int

    init(state: WidgetState) {
        self.state = state
        let items = state.snapshot.todayItems
        let isLate = { (item: WidgetSnapshot.Item) in item.isOverdue(at: state.now, calendar: state.calendar) }
        rows = items.filter(isLate) + items.filter { !isLate($0) }
        late = state.snapshot.overdueCount
        (done, total) = state.todayProgress
    }

    var now: Date { state.now }
    var calendar: Calendar { state.calendar }
    var isClear: Bool { rows.isEmpty }
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var dayNumber: String { String(calendar.component(.day, from: now)) }

    /// A row keeps its section while it is being ticked off, so the list does
    /// not reshuffle under the pointer before the app settles it out.
    func isOverdue(_ item: WidgetSnapshot.Item) -> Bool {
        item.isOverdue(at: now, calendar: calendar)
    }

    /// Rows beyond the first `count`. The snapshot caps its rows, so this
    /// counts from the counters, which already exclude rows being ticked off
    /// while those rows stay on screen until the app republishes.
    func hiddenCount(showing count: Int) -> Int {
        let closing = rows.count { state.isClosing($0) }
        let all = max(rows.count, state.snapshot.overdueCount + state.snapshot.dueTodayCount + closing)
        return max(0, all - count)
    }

    /// "2 of 9 done, 3 late" for VoiceOver.
    var progressDescription: String {
        late > 0 ? "\(done) of \(total) done, \(late) late" : "\(done) of \(total) done"
    }
}

// MARK: - Display type

#if RENDER_TODAY
extension TodayWidget {
    static var renderCases: [RenderCase] {
        let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        let view = { (entry: SnapshotEntry, family: WidgetFamily, style: WidgetStyle) in
            TodayWidgetView(entry: entry, family: family, style: style)
        }
        return RenderCase.families("today", families, view: view)
            + RenderCase.families("today", families, state: "closing", entry: .mockup(pending: [.completing("q4")]), view: view)
            + RenderCase.families("today", families, state: "clear", entry: clearEntry(done: true), view: view)
            + RenderCase.families("today", families, state: "empty", entry: clearEntry(done: false), view: view)
            + RenderCase.families("today", families, state: "short", entry: shortTitlesEntry, view: view)
            + RenderCase.families("today", families, state: "sans", entry: sansEntry, view: view)
            // A three-digit backlog: "128 late" beside the small title, and
            // "14 of 165" beside the medium ring.
            + RenderCase.families("today", families, state: "backlog", entry: backlogEntry(overdue: 128), view: view)
            // Four digits: only the count fits beside the small title.
            + RenderCase.families("today", [.systemSmall, .systemMedium], state: "pileup", entry: backlogEntry(overdue: 1280), view: view)
            + [RenderCase("today", .systemMedium, state: "placeholder", entry: placeholderEntry, view: view)]
    }

    /// Everything due is done (or nothing was due).
    private static func clearEntry(done: Bool) -> SnapshotEntry {
        let base = SnapshotEntry.mockup()
        var snapshot = base.snapshot
        snapshot.todayItems = []
        snapshot.overdueCount = 0
        snapshot.dueTodayCount = 0
        if !done { snapshot.completedTodayCount = 0 }
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: base.state.calendar)
    }

    /// One-line titles, so the small family has room for "+N more" at the
    /// design's spacing.
    private static var shortTitlesEntry: SnapshotEntry {
        let base = SnapshotEntry.mockup()
        var snapshot = base.snapshot
        for index in snapshot.todayItems.indices {
            snapshot.todayItems[index].title = ["Retro actions", "Nishiki tour", "Bathroom tap", "Q3 OKRs"][index % 4]
        }
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: base.state.calendar)
    }

    /// Far more late work than the rows show, with some of today done.
    private static func backlogEntry(overdue: Int) -> SnapshotEntry {
        let base = SnapshotEntry.mockup()
        var snapshot = base.snapshot
        snapshot.overdueCount = overdue
        snapshot.dueTodayCount = 23
        snapshot.completedTodayCount = 14
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: base.state.calendar)
    }

    /// The app's serif-titles setting turned off.
    private static var sansEntry: SnapshotEntry {
        let base = SnapshotEntry.mockup()
        var snapshot = base.snapshot
        snapshot.serifTitles = false
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: base.state.calendar)
    }

    private static var placeholderEntry: SnapshotEntry {
        let base = SnapshotEntry.mockup()
        return SnapshotEntry(date: base.date, snapshot: WidgetSnapshot(), isPlaceholder: true, calendar: base.state.calendar)
    }
}
#endif
