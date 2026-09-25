//
//  AgendaLayout.swift
//  OpenlistWidget
//

import CoreGraphics
import Foundation

/// One day column of the agenda.
nonisolated struct AgendaDay: Equatable, Identifiable, Sendable {
    /// Start of the day.
    var date: Date
    var isToday: Bool
    /// "Wed 23"; uppercase it in the view.
    var label: String
    /// Meetings first, then planned blocks, each by start. Drawing in this
    /// order keeps task blocks on top where the two touch.
    var events: [WidgetSnapshot.AgendaEvent]

    var id: Date { date }
    var meetingCount: Int { events.count { $0.kind == .meeting } }
    var plannedCount: Int { events.count { $0.kind == .task } }
}

/// Where an event sits among others that overlap it: column `index` of `count`.
nonisolated struct AgendaColumn: Equatable, Sendable {
    var index: Int
    var count: Int
}

/// An event's block inside its day column, measured from the column's
/// left edge and the window's top.
nonisolated struct AgendaPlacement: Equatable, Identifiable, Sendable {
    var event: WidgetSnapshot.AgendaEvent
    var rect: CGRect

    var id: String { event.id }
}

/// The hours an agenda draws, and the maths that places things inside them.
nonisolated struct AgendaWindow: Equatable, Sendable {
    /// Whole hours, 0...24.
    var startHour: Int
    var endHour: Int

    var hours: Int { endHour - startHour }

    /// Height of one hour when the window fills up to `height` points. Whole
    /// points keep every hairline on the pixel grid; the remainder is left
    /// below the grid.
    func hourHeight(in height: CGFloat) -> CGFloat {
        max(1, (height / CGFloat(max(1, hours))).rounded(.down))
    }

    /// Hours to label in the gutter: every `step` hours from the first full
    /// hour inside the window, so labels never sit on the top or bottom edge.
    func labelHours(step: Int = 2) -> [Int] {
        guard startHour + 1 < endHour else { return [] }
        return Array(stride(from: startHour + 1, to: endHour, by: step))
    }

    /// Distance from the top of the window to `date`, clamped to the window.
    func offset(for date: Date, hourHeight: CGFloat, calendar: Calendar = .current) -> CGFloat {
        let hour = min(Double(endHour), max(Double(startHour), AgendaLayout.hourOfDay(date, calendar: calendar)))
        return CGFloat(hour - Double(startHour)) * hourHeight
    }

    /// The block for an event, as the design draws it: a point of air above
    /// and below, and never shorter than one line of text.
    func frame(
        for event: WidgetSnapshot.AgendaEvent,
        hourHeight: CGFloat,
        minimumHeight: CGFloat = 13,
        gap: CGFloat = 1,
        calendar: Calendar = .current
    ) -> (top: CGFloat, height: CGFloat) {
        let top = offset(for: event.start, hourHeight: hourHeight, calendar: calendar)
        let bottom = calendar.isDate(event.end, inSameDayAs: event.start)
            ? offset(for: event.end, hourHeight: hourHeight, calendar: calendar)
            : CGFloat(hours) * hourHeight
        return (top + gap, max(minimumHeight, bottom - top - gap * 2))
    }

    /// Every event's block in a day column `width` points wide, `inset` in
    /// from either side. Events that overlap share the width side by side.
    ///
    /// An event shorter than `minimumHeight`, one line of title, still draws
    /// that tall, so it can run into one that starts soon after it. The later
    /// block then cuts it short at its own top instead of moving it aside, as
    /// long as that leaves `shortestHeight`. A long day's hours are shorter,
    /// and back-to-back half-hours would otherwise all split into half-width
    /// columns; only a block cut shorter than that, like a ten-minute task
    /// straight before another, moves aside.
    func blocks(
        for events: [WidgetSnapshot.AgendaEvent],
        hourHeight: CGFloat,
        width: CGFloat,
        inset: CGFloat,
        minimumHeight: CGFloat = 13,
        shortestHeight: CGFloat = 9,
        gap: CGFloat = 1,
        columnGap: CGFloat = 2,
        calendar: Calendar = .current
    ) -> [AgendaPlacement] {
        // Overlap is judged on the blocks as drawn, not on the clock: grown to
        // `shortestHeight`, an event just touches, and so shares a column
        // with, the closest block that may cut it that short.
        let reach = Double(shortestHeight / hourHeight) * 3600
        let drawn = events.map { event in
            var event = event
            event.end = max(event.end, event.start.addingTimeInterval(reach))
            return event
        }
        let columns = AgendaLayout.columns(for: drawn)
        let available = width - inset * 2
        let placed = events.map { event in
            let span = frame(for: event, hourHeight: hourHeight, minimumHeight: minimumHeight, gap: gap, calendar: calendar)
            let column = columns[event.id] ?? AgendaColumn(index: 0, count: 1)
            let gaps = columnGap * CGFloat(column.count - 1)
            let columnWidth = max(0, (available - gaps) / CGFloat(column.count))
            let x = inset + CGFloat(column.index) * (columnWidth + columnGap)
            return AgendaPlacement(event: event, rect: CGRect(x: x, y: span.top, width: columnWidth, height: span.height))
        }
        // Stop each block at the top of the next one below it, so it is never
        // drawn under it. The title clips inside the block instead.
        return placed.map { block in
            let below = placed.lazy
                .filter { $0.rect.minY > block.rect.minY && $0.rect.minX < block.rect.maxX && block.rect.minX < $0.rect.maxX }
                .map(\.rect.minY)
                .min()
            guard let below, below < block.rect.maxY else { return block }
            var cut = block
            cut.rect.size.height = below - block.rect.minY
            return cut
        }
    }

    /// Where the red now line sits, or `nil` outside the window.
    func nowOffset(_ now: Date, hourHeight: CGFloat, calendar: Calendar = .current) -> CGFloat? {
        let hour = AgendaLayout.hourOfDay(now, calendar: calendar)
        guard hour >= Double(startHour), hour <= Double(endHour) else { return nil }
        return CGFloat(hour - Double(startHour)) * hourHeight
    }
}

/// Pure helpers behind the Agenda widget.
nonisolated enum AgendaLayout {
    /// Today's column.
    static func day(_ date: Date, snapshot: WidgetSnapshot, now: Date, calendar: Calendar = .current) -> AgendaDay {
        let start = calendar.startOfDay(for: date)
        let events = snapshot.agenda.filter { calendar.isDate($0.start, inSameDayAs: start) }
        return AgendaDay(
            date: start,
            isToday: calendar.isDate(start, inSameDayAs: now),
            label: WidgetFormat.dayLabel(start, calendar: calendar),
            events: events.sorted { ($0.kind == .meeting ? 0 : 1, $0.start) < ($1.kind == .meeting ? 0 : 1, $1.start) }
        )
    }

    /// The seven days of the week containing `now`, starting on the app's
    /// first weekday (or the published `weekStart` when it covers today).
    static func week(snapshot: WidgetSnapshot, now: Date, calendar: Calendar = .current) -> [AgendaDay] {
        let first = weekStart(snapshot: snapshot, now: now, calendar: calendar)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first).map { day($0, snapshot: snapshot, now: now, calendar: calendar) }
        }
    }

    /// The first day of the week the agenda shows.
    static func weekStart(snapshot: WidgetSnapshot, now: Date, calendar: Calendar = .current) -> Date {
        if let published = snapshot.weekStart,
           let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: published)),
           published <= now, now < end {
            return calendar.startOfDay(for: published)
        }
        // A snapshot from last week (the app has not run since): fall back to
        // this week's own start so the columns still line up with today.
        return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    /// The hours to draw: at least `minimumStart` to `minimumEnd`, widened to
    /// fit every event (and `now`, when given).
    static func window(
        for events: [WidgetSnapshot.AgendaEvent],
        including now: Date? = nil,
        minimumStart: Int = 9,
        minimumEnd: Int = 19,
        calendar: Calendar = .current
    ) -> AgendaWindow {
        var start = Double(minimumStart), end = Double(minimumEnd)
        for event in events {
            start = min(start, hourOfDay(event.start, calendar: calendar))
            end = max(end, calendar.isDate(event.end, inSameDayAs: event.start) ? hourOfDay(event.end, calendar: calendar) : 24)
        }
        if let now {
            let hour = hourOfDay(now, calendar: calendar)
            start = min(start, hour)
            end = max(end, hour)
        }
        let first = max(0, min(23, Int(start.rounded(.down))))
        return AgendaWindow(startHour: first, endHour: min(24, max(first + 1, Int(end.rounded(.up)))))
    }

    /// Side-by-side columns for events that overlap in time. Events that only
    /// touch (one ends as the next starts) share a column.
    static func columns(for events: [WidgetSnapshot.AgendaEvent]) -> [String: AgendaColumn] {
        var result: [String: AgendaColumn] = [:]
        var cluster: [(id: String, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for member in cluster { result[member.id] = AgendaColumn(index: member.column, count: columnEnds.count) }
            cluster = []
            columnEnds = []
        }

        // By start; when two start together, the longer one takes the first column.
        for event in events.sorted(by: { ($0.start, $1.end) < ($1.start, $0.end) }) {
            if event.start >= clusterEnd { closeCluster() }
            let column = columnEnds.firstIndex { $0 <= event.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(event.end) } else { columnEnds[column] = event.end }
            cluster.append((event.id, column))
            clusterEnd = max(clusterEnd, event.end)
        }
        closeCluster()
        return result
    }

    /// "Wed 23 · 4 meetings · 5 planned", leaving out whichever count is
    /// zero, or "Wed 23 · Nothing planned" when both are.
    static func summary(for day: AgendaDay) -> String {
        var parts = [day.label]
        if day.meetingCount > 0 { parts.append(WidgetFormat.count(day.meetingCount, "meeting")) }
        if day.plannedCount > 0 { parts.append("\(day.plannedCount) planned") }
        if parts.count == 1 { parts.append("Nothing planned") }
        return parts.joined(separator: " · ")
    }

    /// The clock time as hours (10:40 is 10.667). Read from the clock rather
    /// than measured from midnight, so a day with a daylight-saving change
    /// still places 10:00 at ten.
    static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }
}
