//
//  NextTodaySchedule.swift
//  openlist
//

import SwiftUI

/// The sizes Today's schedule is drawn at.
private enum NXDay {
    /// The schedule column beside the tasks.
    static let column: CGFloat = 288
    static let gap: CGFloat = 32
    /// The narrowest the task groups get beside the column.
    static let tasks: CGFloat = 480
    /// The page width the column needs: the tasks, the gap and the column.
    static let fits: CGFloat = tasks + gap + column
    static let hourHeight: CGFloat = 40
    /// The hour labels' gutter, which the now and next lines' labels share,
    /// so their titles line up with the day's items.
    static let gutter: CGFloat = 44
    /// Room above the first hour line and below the last for their labels.
    static let labelRoom: CGFloat = 7
    /// A meeting's details beside the column.
    static let detailsWidth: CGFloat = 248
    /// Sessions' and meetings' 11/1.25 titles and 10/1.3 times over
    /// SwiftUI's lines.
    static let titleLeading = 11 * 1.25 - NX.lineHeight(11)
    static let timeLeading = 10 * 1.3 - NX.lineHeight(10)

    /// "40 min", "1h 20m".
    static func span(_ minutes: Int) -> String { minutes < 60 ? "\(minutes) min" : NXFormat.minutes(minutes) }

    /// Whole minutes from `now` to `date`, never fewer than one.
    static func minutes(from now: Date, to date: Date) -> Int {
        max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }

    static func range(_ start: Date, _ end: Date) -> String { "\(NXFormat.clock(start))–\(NXFormat.clock(end))" }
}

// MARK: - Layout

/// Today's task groups with the day's schedule. With room, the schedule is a
/// column beside the groups, which stay first and widest; while the inspector
/// is open it gives the inspector that side rather than squeezing the tasks.
/// Without room, it folds to its now and next lines above the groups, the
/// day's hours a click away. Which of the two is decided by the room the page
/// has with no inspector, so opening a task never moves the rows under the
/// pointer.
struct NXTodayWithSchedule<Tasks: View>: View {
    let now: Date
    /// Today's tasks with no time on the calendar yet, which the schedule offers to fit.
    let toPlan: [UUID]
    @ViewBuilder var tasks: () -> Tasks
    /// The page has room for the column whenever no inspector takes it.
    @State private var roomy = true
    /// The column fits beside the tasks as the page is now.
    @State private var fits = true

    var body: some View {
        let needs = NXDay.fits
        VStack(alignment: .leading, spacing: 0) {
            if !roomy {
                NXTodaySchedule(now: now, toPlan: toPlan, presentation: .strip)
                    // A meeting's details can hang over the groups below.
                    .zIndex(1)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) { tasks() }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if roomy && fits {
                    NXTodaySchedule(now: now, toPlan: toPlan, presentation: .column)
                        .frame(width: NXDay.column)
                        .padding(.leading, NXDay.gap)
                }
            }
            .onGeometryChange(for: Bool.self, of: { $0.size.width >= needs }) { fits = $0 }
        }
        .background { NXTodayRoom(roomy: $roomy) }
    }
}

/// Says whether the page has room for the schedule column with no inspector
/// open, counting a sidebar folded away for the inspector's sake as still
/// there. Only this reads the room, so a live resize redraws nothing else
/// until the answer changes.
private struct NXTodayRoom: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nxPageRoom) private var room
    @Binding var roomy: Bool

    var body: some View {
        let sidebar: CGFloat = env.workbench.isSidebarFoldedForRoom ? 236 : 0
        // The page's padded column, at most the reading measure, less its 40pt margins.
        let width = min(max(0, room - sidebar), NXPageMeasure.reading + 80) - 80
        Color.clear
            .onChange(of: width >= NXDay.fits, initial: true) { _, wide in
                if roomy != wide { roomy = wide }
            }
    }
}

// MARK: - Schedule

private enum NXSchedulePresentation { case column, strip }

/// Today's meetings and planned task sessions: what's on now and next, then
/// the rest of the day on its hours, with a now line. Meetings and sessions
/// differ by form, not colour: a meeting is a quiet grey block, a session a
/// card with its checkbox in its list's colour, as the Calendar draws it.
/// It reads what the Calendar draws and plans nothing itself; Plan, Find a
/// Slot and Fit into calendar show here as they land.
private struct NXTodaySchedule: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let now: Date
    let toPlan: [UUID]
    let presentation: NXSchedulePresentation
    /// The day's meetings, read again only when the calendars reload.
    @State private var meetings = WidgetSnapshotSources.MeetingCache()
    @State private var connecting = false

    /// The folded strip's hours, opened this session.
    private static let dayGroup = "today.schedule.day"
    /// The earlier part of the day, shown this session.
    private static let earlierGroup = "today.schedule.earlier"

    var body: some View {
        let workbench = env.workbench
        let schedule = makeSchedule()
        let external = env.calendar.externalCalendars
        let connected = external.isFixture || external.isAuthorized
        let open = presentation == .column || workbench.collapsedGroups.contains(Self.dayGroup)
        let showsEarlier = workbench.collapsedGroups.contains(Self.earlierGroup)
        let hours = schedule.hours(showsEarlier: showsEarlier)
        let earlier = schedule.earlier(than: schedule.hours(showsEarlier: false))
        let shown = schedule.shown(in: hours)
        VStack(alignment: .leading, spacing: 0) {
            head(open: open, collapsible: presentation == .strip && !schedule.isEmpty)
            if !schedule.holds.isEmpty {
                holds(schedule.holds)
            }
            if schedule.isEmpty {
                empty(connected: connected, unavailable: external.isConnected && !connected)
            } else {
                NXScheduleSummary(schedule: schedule, now: now, sideBySide: presentation == .strip)
                    .padding(.top, 4)
                if open {
                    if !earlier.isEmpty {
                        earlierToggle(count: earlier.count, shown: showsEarlier)
                    }
                    if !shown.isEmpty {
                        NXScheduleGrid(schedule: schedule, hours: hours, items: shown, now: now,
                                       details: presentation == .column ? .leading : .bottom)
                            .padding(.top, earlier.isEmpty ? 12 : 4)
                            // A meeting's details hang over the lines below it.
                            .zIndex(1)
                    }
                }
                if !connected {
                    connectLine(unavailable: external.isConnected)
                }
            }
            if !toPlan.isEmpty {
                planLine(toPlan)
            }
        }
        // Level with the first group's head beside it, or, folded above the
        // groups, as far below the header as they are.
        .padding(.top, 22)
        .padding(.bottom, presentation == .strip ? 6 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule")
    }

    private func makeSchedule() -> TodaySchedule {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let coordinator = env.calendar
        let store = env.store
        let closing = env.workbench.closing
        return TodaySchedule(blocks: coordinator.visibleBlocks,
                             busy: meetings.busyTimes(in: DateInterval(start: day, end: end), from: coordinator.externalCalendars),
                             now: now, calendar: cal,
                             title: { store.block(id: $0.taskID)?.displayTitle ?? $0.titleSnapshot ?? "Task" },
                             isDone: { block in
                                 block.isCompleted || store.block(id: block.taskID)?.isCompleted == true || closing[block.taskID] != nil
                             })
    }

    // MARK: Parts

    /// "Schedule", as a group's head: in the strip it folds the day's hours.
    private func head(open: Bool, collapsible: Bool) -> some View {
        HStack(spacing: 7) {
            let title = HStack(spacing: 7) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NX.ink(0.45))
                    .accessibilityHidden(true)
                Text("Schedule")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .fixedSize()
                if collapsible {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NX.ink(0.36))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(style.slides ? NX.cssEase(180) : nil, value: open)
                        .accessibilityHidden(true)
                }
            }
            if collapsible {
                Button { toggle(Self.dayGroup) } label: { title }
                    .buttonStyle(NXBareButtonStyle(radius: 6))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(open ? "Expanded" : "Collapsed")
                    .help(open ? "Hide the day’s hours" : "Show the day’s hours")
            } else {
                title
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Button { env.workbench.showOnCalendar(now) } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 6,
                                            padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                            foreground: NX.ink(0.45), hoverForeground: NX.ink))
            .help("Open Calendar (⌘3)")
            .accessibilityLabel("Open Calendar")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture { if collapsible { toggle(Self.dayGroup) } }
    }

    /// The day's all-day holds, like Out of office, which Plan keeps clear of.
    private func holds(_ holds: [FixedBusyTime]) -> some View {
        let names = holds.map { $0.title.isEmpty ? "Busy" : $0.title }
        return HStack(spacing: 6) {
            Text("All day")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(NX.textTertiary)
            Text(names.joined(separator: ", "))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NX.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(NX.ink(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(names.joined(separator: ", "))
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    /// Nothing today: said quietly, with a light way to connect a calendar
    /// when none is.
    @ViewBuilder
    private func empty(connected: Bool, unavailable: Bool) -> some View {
        if presentation == .strip {
            // Above the groups, one line: the button's help says the rest.
            HStack(spacing: 10) {
                Text("Nothing scheduled today.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(NX.textTertiary)
                if !connected { connectButton(unavailable: unavailable) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
        } else {
            emptyColumn(connected: connected, unavailable: unavailable)
        }
    }

    private func emptyColumn(connected: Bool, unavailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing scheduled today.")
                .font(.system(size: 12.5))
                .foregroundStyle(NX.textTertiary)
            if !connected {
                Text(unavailable ? "Openlist can’t read your calendars. Allow access in System Settings to see your meetings here."
                                 : "Connect a calendar to see your meetings beside your tasks.")
                    .font(.system(size: 12))
                    .foregroundStyle(NX.textQuaternary)
                    .fixedSize(horizontal: false, vertical: true)
                connectButton(unavailable: unavailable)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    /// Under a schedule of sessions alone: meetings would show with them.
    private func connectLine(unavailable: Bool) -> some View {
        HStack(spacing: 8) {
            Text(unavailable ? "Calendars unavailable." : "No calendar connected.")
                .font(.system(size: 11.5))
                .foregroundStyle(NX.textQuaternary)
            connectButton(unavailable: unavailable)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
    }

    /// Connects the Mac's calendars as Settings › Planning does, or, once
    /// access was turned down, opens Settings, where the reason shows.
    private func connectButton(unavailable: Bool) -> some View {
        Button {
            if unavailable {
                env.workbench.go(.settings)
                return
            }
            connecting = true
            Task {
                let external = env.calendar.externalCalendars
                await external.requestAccess()
                env.calendar.refreshCalendars()
                connecting = false
                // Turned down: Settings says why and how to allow it.
                if !external.isAuthorized { env.workbench.go(.settings) }
            }
        } label: {
            Text(unavailable ? "Open Settings" : connecting ? "Connecting…" : "Connect Calendars")
                .padding(.vertical, (11 - NX.lineHeight(11)) / 2)
        }
        .font(.system(size: 11, weight: .semibold))
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.09), rest: NX.ink(0.05), radius: 6,
                                        padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                        foreground: NX.textSecondary, hoverForeground: NX.ink))
        .disabled(connecting)
        .help(unavailable ? "Open Settings" : "Read your Mac’s calendars, so meetings show here and Plan works around them")
    }

    /// The earlier part of the day, folded away until asked for.
    private func earlierToggle(count: Int, shown: Bool) -> some View {
        Button { toggle(Self.earlierGroup) } label: {
            HStack(spacing: 5) {
                Text(shown ? "Hide earlier" : "Earlier today")
                    .font(.system(size: 11.5, weight: .medium))
                if !shown {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(NX.textQuaternary)
                }
                Image(systemName: shown ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                        padding: EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6),
                                        foreground: NX.textTertiary, hoverForeground: NX.ink))
        .padding(.leading, NXDay.gutter - 6)
        .padding(.top, 10)
        .accessibilityLabel(shown ? "Hide earlier" : "Earlier today, \(count)")
    }

    /// Today's tasks with no time yet, and the way to give them one: each
    /// into the next free slot, as Find a Slot does, in one Undo.
    private func planLine(_ ids: [UUID]) -> some View {
        HStack(spacing: 8) {
            Text(ids.count == 1 ? "1 task for today has no time yet" : "\(ids.count) tasks for today have no time yet")
                .font(.system(size: 11.5))
                .foregroundStyle(NX.textTertiary)
                .contentTransition(.numericText())
            Spacer(minLength: 4)
            Button { env.workbench.fit(ids) } label: {
                Image(systemName: "sparkles").font(.system(size: 11)).frame(height: 13)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                            padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                            foreground: NX.ink(0.5), hoverForeground: NX.ink))
            .help(ids.count == 1 ? "Find it a slot on the calendar" : "Find each a slot on the calendar")
            .accessibilityLabel("Fit into calendar")
        }
        .padding(.leading, 10)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ group: String) {
        let workbench = env.workbench
        if workbench.collapsedGroups.contains(group) { workbench.collapsedGroups.remove(group) }
        else { workbench.collapsedGroups.insert(group) }
    }
}

// MARK: - Now and next

/// What's on now and what comes next, as two quiet lines over the day: the
/// one under way heavier, a meeting's place or a session's list after its time.
private struct NXScheduleSummary: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let schedule: TodaySchedule
    let now: Date
    /// Above the groups, now and next share a line where they fit.
    var sideBySide = false

    var body: some View {
        Group {
            if sideBySide {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) { lines.frame(maxWidth: 360, alignment: .leading) }
                    VStack(alignment: .leading, spacing: 9) { lines }
                }
            } else {
                VStack(alignment: .leading, spacing: 9) { lines }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var lines: some View {
        ForEach(Array(schedule.current.prefix(2).enumerated()), id: \.element.id) { index, item in
            line(label: index == 0 ? "Now" : "", item: item, current: true)
        }
        if let next = schedule.next {
            line(label: "Next", item: next, current: false)
        }
        if !schedule.hasRest {
            Text("Nothing else scheduled today.")
                .font(.system(size: 12.5))
                .foregroundStyle(NX.textTertiary)
                .padding(.leading, NXDay.gutter - 10)
        }
    }

    private func line(label: String, item: TodaySchedule.Item, current: Bool) -> some View {
        let task = item.taskID.flatMap { env.store.block(id: $0) }
        let list = library.list(task?.listID)
        let time = item.isActive ? "Working, until \(NXFormat.clock(item.end))"
            : current ? "until \(NXFormat.clock(item.end))"
            : "\(NXFormat.clock(item.start)) · in \(NXDay.span(NXDay.minutes(from: now, to: item.start)))"
        let place = item.kind == .meeting ? item.meeting?.location : list?.displayTitle
        let detail = [time, place].compactMap { $0 }.joined(separator: " · ")
        // Start where a session is planned now and nothing's in hand, as the
        // Calendar's Planned now banner offers it.
        let startable = current && item.kind == .session && !item.isActive && env.workbench.workTask == nil
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(NX.textTertiary)
                .frame(width: NXDay.gutter - 10, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: current ? .semibold : .medium))
                    .foregroundStyle(NX.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    if item.kind == .session, let list {
                        Circle().fill(list.nxColor).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(NX.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if startable, let taskID = item.taskID {
                Button { env.workbench.startWork(taskID) } label: {
                    Image(systemName: "play.fill").font(.system(size: 9.5)).frame(width: 12, height: 12)
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.primaryButtonHover, rest: NX.primaryButton, radius: 12,
                                                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                                                foreground: NX.onPrimary, hoverForeground: NX.onPrimary))
                .help("Start working")
                .accessibilityLabel("Start working on \(item.title)")
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let taskID = item.taskID else { return }
            env.workbench.click(taskID, command: NXModifiers.command, shift: NXModifiers.shift)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label.isEmpty ? "Also now" : label): \(item.title)")
        .accessibilityValue(detail)
    }
}

// MARK: - The day's hours

/// The rest of the day on its hours: hour lines and labels, meetings and
/// sessions in lanes as the Calendar lays them out, and the now line.
private struct NXScheduleGrid: View {
    @Environment(\.nextStyle) private var style
    @Environment(\.displayScale) private var displayScale
    let schedule: TodaySchedule
    let hours: ClosedRange<Int>
    let items: [TodaySchedule.Item]
    let now: Date
    /// Where a meeting's details show: beside the column, or under the
    /// meeting where the hours span the page.
    let details: Edge
    /// The meeting whose details show, once the pointer has rested on it.
    @State private var detailsID: String?
    @State private var hoveredID: String?

    private var height: CGFloat { CGFloat(hours.upperBound - hours.lowerBound) * NXDay.hourHeight }

    /// Where `time` falls, by the clock, clamped to the hours drawn.
    private func top(_ time: Date) -> CGFloat {
        let hour = min(max(schedule.hour(time), Double(hours.lowerBound)), Double(hours.upperBound))
        return CGFloat(hour - Double(hours.lowerBound)) * NXDay.hourHeight
    }

    var body: some View {
        let layout = arrange()
        let nowHour = schedule.hour(now)
        let nowY: CGFloat? = nowHour >= Double(hours.lowerBound) && nowHour <= Double(hours.upperBound) ? top(now) : nil
        HStack(alignment: .top, spacing: 0) {
            gutter(nowY: nowY)
                .frame(width: NXDay.gutter, height: height, alignment: .topTrailing)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // What's gone by today, a shade darker.
                    if let nowY { NX.ink(0.018).frame(height: nowY) }
                    ForEach(Array(hours), id: \.self) { hour in
                        Rectangle().fill(NX.ink(0.07))
                            .frame(height: 1 / displayScale)
                            .offset(y: CGFloat(hour - hours.lowerBound) * NXDay.hourHeight)
                    }
                    // The now line runs between the day's items, not through
                    // their words; its dot and the time in the gutter stay on top.
                    if let nowY {
                        Rectangle().fill(NX.red)
                            .frame(width: max(0, geo.size.width - 1), height: 1.5)
                            .offset(y: nowY - 0.75)
                            .allowsHitTesting(false)
                    }
                    ForEach(items) { item in
                        if let slot = item.layoutID.flatMap({ layout[$0] }) {
                            entry(item, height: slot.height, width: width(slot, geo.size.width))
                                .frame(width: width(slot, geo.size.width), height: slot.height)
                                .offset(x: x(slot, geo.size.width), y: slot.top)
                                .zIndex(item.kind == .session ? 2 : 1)
                        }
                    }
                    if let nowY {
                        Circle().fill(NX.red)
                            .frame(width: 7, height: 7)
                            .offset(x: -3.5, y: nowY - 3.5)
                            .allowsHitTesting(false)
                            .zIndex(5)
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .topLeading)
                // Over the grid, never part of its layout.
                .overlay(alignment: .topLeading) {
                    if let id = detailsID, let item = items.first(where: { $0.id == id }), let meeting = item.meeting,
                       let slot = item.layoutID.flatMap({ layout[$0] }) {
                        NXMeetingDetails(meeting: meeting, now: now)
                            .frame(width: NXDay.detailsWidth)
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(x: details == .leading ? -(NXDay.gutter + 10 + NXDay.detailsWidth)
                                        : max(0, min(x(slot, geo.size.width), geo.size.width - NXDay.detailsWidth)),
                                    y: details == .leading ? slot.top - 4 : slot.top + slot.height + 6)
                            .transition(style.slides ? .opacity.combined(with: .offset(x: details == .leading ? 4 : 0,
                                                                                         y: details == .leading ? 0 : -4))
                                                     : .opacity)
                            .allowsHitTesting(false)
                    }
                }
                // Blocks that move, as a replan or a plan moves them, glide
                // there; with Reduce Motion they're simply there.
                .animation(style.slides ? style.ease(320) : nil,
                           value: layout.mapValues { [$0.top, $0.height, Double($0.lane), Double($0.laneCount)] })
            }
            .frame(height: height)
        }
        .padding(.vertical, NXDay.labelRoom)
        .task(id: hoveredID) {
            // The pointer resting on a meeting shows its details, as a
            // tooltip waits; moving off hides them at once.
            guard let id = hoveredID else {
                withAnimation(NX.ease(120)) { detailsID = nil }
                return
            }
            if detailsID != nil {
                withAnimation(NX.ease(120)) { detailsID = id }
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(NX.ease(160)) { detailsID = id }
        }
    }

    @ViewBuilder
    private func entry(_ item: TodaySchedule.Item, height: CGFloat, width: CGFloat) -> some View {
        let emphasis: NXScheduleEmphasis = item.isCurrent(at: now) ? .current : schedule.next?.id == item.id ? .next : .none
        if let meeting = item.meeting {
            NXScheduleMeeting(meeting: meeting, height: height, width: width, now: now, emphasis: emphasis)
                .onHover { inside in
                    if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
                }
        } else if let block = item.block {
            NXScheduleSession(block: block, title: item.title, height: height, width: width, now: now, emphasis: emphasis)
        }
    }

    private func gutter(nowY: CGFloat?) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(hours), id: \.self) { hour in
                Text(String(format: "%02d:00", hour % 24))
                    .font(NX.mono(9.5))
                    .foregroundStyle(NX.textQuaternary)
                    .padding(.trailing, 8)
                    .offset(y: CGFloat(hour - hours.lowerBound) * NXDay.hourHeight - 6)
                    // A label the now pill sits on gives way to it.
                    .opacity(nowY.map { abs($0 - CGFloat(hour - hours.lowerBound) * NXDay.hourHeight) < 15 } == true ? 0 : 1)
                    .accessibilityHidden(true)
            }
            if let nowY {
                Text(NXFormat.clock(now))
                    .font(NX.mono(9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(NX.red, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.trailing, 4)
                    .offset(y: nowY - 7.5)
                    .accessibilityLabel("Now, \(NXFormat.clock(now))")
            }
        }
    }

    private func x(_ slot: CalendarOverlapLayout.Placement, _ width: CGFloat) -> CGFloat {
        slot.laneCount > 1 ? width * CGFloat(slot.lane) / CGFloat(slot.laneCount) + 2 : 3
    }

    private func width(_ slot: CalendarOverlapLayout.Placement, _ width: CGFloat) -> CGFloat {
        max(0, slot.laneCount > 1 ? width / CGFloat(slot.laneCount) - 4 : width - 4)
    }

    /// Lanes over the items' times, as the Calendar's day column has them.
    private func arrange() -> [String: CalendarOverlapLayout.Placement] {
        let y = { (time: Date) in Double(top(time)) }
        let laid = items.compactMap { item -> CalendarOverlapLayout.Item? in
            if let meeting = item.meeting { return .event(meeting, y: y) }
            return item.block.map { .block($0, y: y) }
        }
        return Dictionary(CalendarOverlapLayout.arrange(laid).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

private extension TodaySchedule.Item {
    /// The id the Calendar's lanes know it by.
    var layoutID: String? { meeting?.id ?? block?.id }
}

/// What's under way, what comes next, and the rest, drawn heavier to lighter.
private enum NXScheduleEmphasis { case current, next, none }

/// A meeting: a quiet grey block, its title in the secondary ink, darker and
/// in full ink while it's on.
private struct NXScheduleMeeting: View {
    let meeting: FixedBusyTime
    let height: CGFloat
    /// Its lane's width: a narrow one keeps its room for the title.
    let width: CGFloat
    let now: Date
    let emphasis: NXScheduleEmphasis

    var body: some View {
        let past = meeting.end <= now
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let title = Text(meeting.title.isEmpty ? "Busy" : meeting.title)
            .font(.system(size: 11, weight: emphasis == .current ? .semibold : .medium))
            .foregroundStyle(emphasis == .current ? NX.ink : past ? NX.textTertiary : NX.textSecondary)
        Group {
            if height >= 32 {
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .lineSpacing(NXDay.titleLeading)
                        .padding(.vertical, NXDay.titleLeading / 2)
                    Text(NXDay.range(meeting.start, meeting.end))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(NX.textTertiary)
                        .lineSpacing(NXDay.timeLeading)
                        .padding(.vertical, NXDay.timeLeading / 2)
                }
            } else {
                // Too short for a second line: its start trails the title.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title.lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if width >= 150 {
                        Text(NXFormat.clock(meeting.start))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(NX.textTertiary)
                            .fixedSize()
                    }
                }
                .padding(.vertical, NXDay.titleLeading / 2)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(NX.ink(emphasis == .current ? 0.085 : past ? 0.035 : 0.055), in: shape)
        // Solid, so the now line passes under it.
        .background(NX.paper, in: shape)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meeting.title.isEmpty ? "Busy" : meeting.title)
        .accessibilityValue(NXMeetingDetails.spoken(meeting))
    }
}

/// A planned task session, drawn as the Calendar draws it (`NXSessionLook`):
/// a grey card with the task's checkbox in its list's colour, work under way
/// solid ink, done a green tint, a slot gone by without work dashed red. On
/// Today what's on now, and next, is outlined a step heavier. A click
/// selects its task, a double-click opens it, as a row's do.
private struct NXScheduleSession: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let block: PlannedBlock
    let title: String
    let height: CGFloat
    /// Its lane's width: a narrow one keeps its room for the title.
    let width: CGFloat
    let now: Date
    let emphasis: NXScheduleEmphasis
    @State private var hovering = false
    @State private var entered = true

    var body: some View {
        let workbench = env.workbench
        let task = env.store.block(id: block.taskID)
        let closing = workbench.closing[block.taskID] != nil
        let done = block.isCompleted || task?.isCompleted == true || closing
        let working = block.isActive || env.calendar.pausedBlockID == block.id
        let missed = !block.isActive && !done && block.end <= now
        let focused = workbench.focusID == block.taskID || env.navigator.openTaskID == block.taskID
        let list = library.list(task?.listID)
        let movable = block.placementID != nil && !block.isActive && !done && task?.occurrenceID == block.occurrenceID
        // The Calendar's look, so a session reads the same on both screens.
        let look = NXSessionLook(working: working, done: done, missed: missed, listColor: list?.nxColor)
        // Today draws what's on now, and next, a step heavier.
        let plain = !working && !done && !missed
        let ring: Color = plain && emphasis == .current ? NX.ink(0.6) : plain && emphasis == .next ? NX.ink(0.3) : look.ring
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let note = note(done: done, working: working, missed: missed)

        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 5) {
                ZStack {
                    if done {
                        // From the accent to green as the completion settles, as the Calendar's.
                        Circle().animation(NX.cssEase(200)) { $0.foregroundStyle(closing ? style.accent : NX.green) }
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .bold))
                            .foregroundStyle(closing ? style.onAccent : .white)
                    } else {
                        Circle().strokeBorder(look.circle, lineWidth: 1.3)
                    }
                }
                .frame(width: 12, height: 12)
                .padding(.top, 1)
                // Wider than the circle it draws, as a row's checkbox is.
                .contentShape(Circle().inset(by: -5))
                .onTapGesture(perform: check)
                .help(done ? "Reopen" : "Mark as done")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .strikethrough(done)
                        .foregroundStyle(look.foreground)
                        .lineLimit(height < 30 ? 1 : nil)
                        .truncationMode(.tail)
                        .lineSpacing(NXDay.titleLeading)
                        .padding(.vertical, NXDay.titleLeading / 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Too short for a second line: its start trails the title.
                    if height < 34, width >= 150 {
                        Text(NXFormat.clock(block.start))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(look.detail)
                            .fixedSize()
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if height >= 34 {
                Text(NXDay.range(block.start, block.end) + (note.map { " · " + $0 } ?? ""))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(look.detail)
                    .lineSpacing(NXDay.timeLeading)
                    .padding(.vertical, NXDay.timeLeading / 2)
                    .padding(.leading, 17)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        // A missed block's content keeps inside its dashed border, as the Calendar's.
        .padding(missed ? 1 : 0)
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(look.fill, in: shape)
        .overlay(RoundedRectangle(cornerRadius: missed ? 6 : 7, style: .continuous)
            .strokeBorder(ring, lineWidth: plain && emphasis == .current ? 1.5 : 1)
            .padding(missed ? 1 : 0))
        .overlay {
            if missed {
                shape.strokeBorder(NXSessionLook.missedDash, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(shape)
        // Selected, or open in the details: the Calendar's focus ring.
        .overlay {
            NXFocusRing(spread: focused ? 2 : 0)
                .fill(style.accent.opacity(focused ? 1 : 0), style: FillStyle(eoFill: true))
                .animation(NX.cssEase(240), value: focused)
                .allowsHitTesting(false)
        }
        .brightness(hovering ? -0.03 : 0)
        // Planned just now: it arrives, as the Calendar's blocks do; with
        // Reduce Motion it fades in.
        .offset(y: entered || !style.slides ? 0 : -6)
        .scaleEffect(entered || !style.slides ? 1 : 0.99)
        .opacity(entered ? 1 : 0)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { workbench.click(block.taskID, command: NXModifiers.command, shift: NXModifiers.shift) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { workbench.inspect(block.taskID) })
        .onChange(of: workbench.freshBlockTaskID == block.taskID, initial: true) { _, fresh in
            guard fresh else { return }
            entered = false
            Task { @MainActor in withAnimation(style.ease(380)) { entered = true } }
        }
        .help("\(title) · \(NXDay.range(block.start, block.end))")
        .contextMenu {
            if movable {
                Button("Remove from Calendar", systemImage: "calendar.badge.minus") { workbench.unplace(block) }
            }
            Button("Show in Calendar", systemImage: "calendar") { workbench.showOnCalendar(block.start) }
            if task != nil {
                Divider()
                NXTaskMenu(ids: [block.taskID])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken(done: done, working: working, missed: missed, list: list?.displayTitle))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { workbench.click(block.taskID, command: false, shift: false) }
        .accessibilityAction(named: "Open details") { workbench.inspect(block.taskID) }
        .accessibilityAction(named: done ? "Reopen" : "Complete", check)
    }

    private func note(done: Bool, working: Bool, missed: Bool) -> String? {
        if done { return nil }
        if missed { return "carried forward" }
        if working { return env.calendar.pausedBlockID == block.id ? "paused" : "working" }
        if emphasis == .current { return "\(NXDay.span(NXDay.minutes(from: now, to: block.end))) left" }
        return nil
    }

    private func spoken(done: Bool, working: Bool, missed: Bool, list: String?) -> String {
        let state = done ? "done" : missed ? "missed, carried forward" : working ? "working" : emphasis == .current ? "now"
            : emphasis == .next ? "next" : nil
        return ["\(NXFormat.clock(block.start)) to \(NXFormat.clock(block.end))", state, list].compactMap { $0 }
            .joined(separator: ", ")
    }

    /// A done block reopens its task where it was, as the Calendar's does.
    private func check() {
        if block.isCompleted { env.workbench.reopen(block: block) } else { env.workbench.toggle(block.taskID) }
    }
}

/// A meeting's details, beside it while the pointer rests there: its title,
/// time and length, how far off it is, and where and which calendar.
private struct NXMeetingDetails: View {
    let meeting: FixedBusyTime
    let now: Date

    var body: some View {
        let minutes = Int((meeting.end.timeIntervalSince(meeting.start) / 60).rounded())
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title.isEmpty ? "Busy" : meeting.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NX.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(NXDay.range(meeting.start, meeting.end)) · \(NXDay.span(minutes))")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NX.textSecondary)
                Text(Self.when(meeting, now: now))
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.textTertiary)
            }
            if meeting.location != nil || meeting.calendarTitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let location = meeting.location { detail("mappin.and.ellipse", location) }
                    if let calendar = meeting.calendarTitle { detail("calendar", calendar) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .nxCardShadow(radius: 10, y: 8, blur: 24)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NX.ink(0.45))
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(NX.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "In 40 min", "Now · 25 min left", "Ended 10 min ago".
    static func when(_ meeting: FixedBusyTime, now: Date) -> String {
        if meeting.start > now { return "In \(NXDay.span(NXDay.minutes(from: now, to: meeting.start)))" }
        if meeting.end > now { return "Now · \(NXDay.span(NXDay.minutes(from: now, to: meeting.end))) left" }
        return "Ended " + NXFormat.relative(meeting.end, now: now)
    }

    /// The details as VoiceOver reads them with the meeting.
    static func spoken(_ meeting: FixedBusyTime) -> String {
        ["\(NXFormat.clock(meeting.start)) to \(NXFormat.clock(meeting.end))", meeting.location,
         meeting.calendarTitle.map { "\($0) calendar" }].compactMap { $0 }.joined(separator: ", ")
    }
}
