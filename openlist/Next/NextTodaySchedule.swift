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
    /// Where the groups' scroll view starts below the header kept in place,
    /// and how far rows fade as they scroll up to it: both within the 22pt
    /// the first group leaves above its head, so they show only once the
    /// groups scroll.
    static let pageEdge: CGFloat = 10
    static let pageFade: CGFloat = 10
    /// The same below now and next, within the 12pt above the hours.
    static let hoursEdge: CGFloat = 4
    static let hoursFade: CGFloat = 8
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

/// Today's page: its header, the task groups and the day's schedule. With
/// room, the schedule is a column beside the groups, which stay first and
/// widest. The header stays put over both, and each side scrolls on its own:
/// the groups in the page's scroll view, the schedule's hours under its now
/// and next lines, so scrolling one never moves the other. While the
/// inspector is open the column gives the inspector that side rather than
/// squeezing the tasks. Without room, the page scrolls as one, as other pages
/// do, with the schedule folded to its now and next lines above the groups
/// and the day's hours a click away, in a scroll of their own at most a third
/// of the page tall, so a long day never pushes the tasks out of sight. A
/// scroll there stays where it started, as on the rest of the Mac: the hours
/// don't hand it on to the page at their end, and the page scrolling past
/// them doesn't scroll them. Which of the two layouts is decided by the room
/// the page has with no inspector, so opening a task never moves the rows
/// under the pointer.
struct NXTodayLayout<Header: View, Tasks: View>: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nxPageRoom) private var room
    /// Row IDs in on-screen order, published for j/k and ⌘A.
    let rowIDs: [UUID]
    let now: Date
    /// Today's tasks with no time on the calendar yet, which the schedule offers to fit.
    let toPlan: [UUID]
    /// Both built once, so laying the page out again as the window resizes
    /// draws neither again.
    let header: Header
    let tasks: Tasks
    /// The pointer rests on the folded schedule's hours, which scroll on
    /// their own above the groups.
    @State private var onHours = false

    init(rowIDs: [UUID], now: Date, toPlan: [UUID], @ViewBuilder header: () -> Header,
         @ViewBuilder tasks: () -> Tasks) {
        self.rowIDs = rowIDs
        self.now = now
        self.toPlan = toPlan
        self.header = header()
        self.tasks = tasks()
    }

    var body: some View {
        let sidebar: CGFloat = env.workbench.isSidebarFoldedForRoom ? 236 : 0
        // The page's padded column with no inspector, at most the reading
        // measure, less its 40pt margins; a sidebar folded away for the
        // inspector's sake counts as still there.
        let roomy = min(max(0, room - sidebar), NXPageMeasure.reading + 80) - 80 >= NXDay.fits
        GeometryReader { page in
            let column = NXPageMeasure.column(measure: NXPageMeasure.reading + 80, room: room, width: page.size.width)
            // The column's 40pt margins, and on a wide display the room
            // either side of it, which each side's scroll view reaches into.
            let leading = column.x + 40
            let trailing = page.size.width - column.x - column.width + 40
            // The schedule fits beside the tasks as the page is now.
            let beside = roomy && column.width - 80 >= NXDay.fits
            VStack(alignment: .leading, spacing: 0) {
                if roomy {
                    header
                        .padding(.top, 26)
                        .padding(.leading, leading)
                        .padding(.trailing, trailing)
                }
                HStack(alignment: .top, spacing: 0) {
                    NXPageScroll(rowIDs: rowIDs, yields: !roomy && onHours) {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 0).id(ContentReveal.Anchor.pageHeader)
                            if !roomy {
                                header
                                NXTodaySchedule(now: now, toPlan: toPlan, presentation: .strip,
                                                hoursCap: max(3 * NXDay.hourHeight, page.size.height / 3))
                                    // A meeting's details can hang over the groups below.
                                    .zIndex(1)
                            }
                            VStack(alignment: .leading, spacing: 0) { tasks }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        // Under the header kept in place, as far up as the
                        // scroll view starts below it and its fade, so the
                        // rows rest where they would on a page that scrolls
                        // as one.
                        .padding(.top, roomy ? -(NXDay.pageEdge + NXDay.pageFade) : 26)
                        .padding(.leading, leading)
                        // Beside the schedule, the gap to it, where the
                        // groups' scroller shows.
                        .padding(.trailing, beside ? NXDay.gap : trailing)
                        .padding(.bottom, 120)
                    }
                    // Below the header kept in place, rows scrolled up go
                    // into a fade rather than being cut off. The scroll view
                    // starts below it, so a row brought into view stops
                    // there, and its offsets stay plain for Back and Forward.
                    .scrollClipDisabled(roomy)
                    .modifier(NXScrollEdgeFade(top: roomy ? NXDay.pageFade : 0, above: true))
                    .padding(.top, roomy ? NXDay.pageEdge + NXDay.pageFade : 0)
                    if beside {
                        NXTodaySchedule(now: now, toPlan: toPlan, presentation: .column)
                            .frame(width: NXDay.column + trailing)
                    }
                }
            }
            .background { NXPageBackground() }
            .onPreferenceChange(NXHoursHoldPageKey.self) { onHours = $0 }
        }
        .modifier(NXPageEntrance())
    }
}

// MARK: - Schedule

private enum NXSchedulePresentation { case column, strip }

/// Today's meetings and planned task sessions: what's on now and next, then
/// the rest of the day on its hours, with a now line. Meetings and sessions
/// differ by form, not colour: a meeting is a quiet grey block, a session a
/// card with its checkbox in its list's colour, as the Calendar draws it.
/// It reads what the Calendar draws and plans nothing itself; Plan, Find a
/// Slot and Fit into calendar show here as they land. Now and next stay put
/// while the hours scroll on their own, starting an hour before now.
private struct NXTodaySchedule: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nxPageScrolling) private var pageScrolling
    let now: Date
    let toPlan: [UUID]
    let presentation: NXSchedulePresentation
    /// The tallest the strip's hours get before they scroll.
    var hoursCap: CGFloat = .infinity
    /// The day's meetings, read again only when the calendars reload.
    @State private var meetings = WidgetSnapshotSources.MeetingCache()
    @State private var connecting = false
    /// The meeting under the pointer, and the one whose details show once
    /// the pointer has rested on it.
    @State private var hoveredID: String?
    @State private var detailsID: String?
    /// The strip's hours, unscrolled, once laid out.
    @State private var hoursHeight: CGFloat?
    @State private var pointerOnHours = false

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
        // From an hour before now, or from the start of what's under way.
        let start = schedule.hours(showsEarlier: false)
        let hours = schedule.hours(showsEarlier: showsEarlier)
        let earlier = schedule.earlier(than: start)
        let shown = schedule.shown(in: hours)
        VStack(alignment: .leading, spacing: 0) {
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
                }
            }
            .frame(width: presentation == .column ? NXDay.column : nil, alignment: .leading)
            let day = VStack(alignment: .leading, spacing: 0) {
                if !earlier.isEmpty {
                    earlierToggle(count: earlier.count, shown: showsEarlier)
                }
                if !shown.isEmpty {
                    NXScheduleGrid(schedule: schedule, hours: hours, start: start.lowerBound, items: shown, now: now,
                                   hoveredID: $hoveredID)
                        .padding(.top, earlier.isEmpty ? 12 : 4)
                }
            }
            switch presentation {
            case .column:
                // The rest of the day scrolls on its own, under now and next,
                // to the column's foot.
                scrolling {
                    VStack(alignment: .leading, spacing: 0) {
                        if !schedule.isEmpty {
                            day
                            if !connected {
                                connectLine(unavailable: external.isConnected)
                            }
                        }
                        if !toPlan.isEmpty {
                            planLine(toPlan)
                        }
                    }
                    .frame(width: NXDay.column, alignment: .topLeading)
                    .padding(.top, -(NXDay.hoursEdge + NXDay.hoursFade))
                    // As the page's foot, so the end clears the bottom bars.
                    .padding(.bottom, 120)
                }
                .safeAreaPadding(.top, NXDay.hoursFade)
                .modifier(NXScrollEdgeFade(top: NXDay.hoursFade))
                .padding(.top, NXDay.hoursEdge)
            case .strip:
                if open && !schedule.isEmpty && !(earlier.isEmpty && shown.isEmpty) {
                    // Above the groups, a long day scrolls in a part of the
                    // page rather than pushing the tasks down.
                    let estimate = CGFloat(hours.upperBound - hours.lowerBound) * NXDay.hourHeight + 40
                    let height = (hoursHeight ?? estimate) - NXDay.hoursEdge
                    let capped = height > hoursCap
                    scrolling {
                        day.onGeometryChange(for: CGFloat.self, of: \.size.height) { hoursHeight = $0 }
                            .padding(.top, -(NXDay.hoursEdge + NXDay.hoursFade))
                    }
                    .safeAreaPadding(.top, NXDay.hoursFade)
                    // A day that fits doesn't scroll, so the page does.
                    .scrollBounceBehavior(.basedOnSize)
                    // A scroll stays where it started: the hours scroll
                    // whenever the page holds still for them, and hold still
                    // while the page scrolls past them.
                    .environment(\.isScrollEnabled, !pageScrolling)
                    // Cut off by the cap, the hours fade at their foot too,
                    // a sign there's more.
                    .modifier(NXScrollEdgeFade(top: NXDay.hoursFade, bottom: capped ? 2 * NXDay.hoursFade : 0))
                    .frame(height: min(height, hoursCap))
                    .onHover { pointerOnHours = $0 }
                    .onDisappear { pointerOnHours = false }
                    // Scrolled to their end, they'd hand the scrolling on to
                    // the page, so it holds still while the pointer rests on
                    // them.
                    .preference(key: NXHoursHoldPageKey.self, value: capped && pointerOnHours)
                    .padding(.top, NXDay.hoursEdge)
                }
                if !schedule.isEmpty && !connected {
                    connectLine(unavailable: external.isConnected)
                }
                if !toPlan.isEmpty {
                    planLine(toPlan)
                }
            }
        }
        // Level with the first group's head beside it, or, folded above the
        // groups, as far below the header as they are.
        .padding(.top, 22)
        .padding(.bottom, presentation == .strip ? 6 : 0)
        .frame(maxHeight: presentation == .column ? .infinity : nil, alignment: .top)
        // A meeting's details, over the schedule rather than in the hours'
        // scroll view, which would cut them off.
        .overlayPreferenceValue(NXMeetingFramesKey.self) { frames in
            GeometryReader { geo in
                if let id = detailsID, let frame = frames[id], let meeting = shown.first(where: { $0.id == id })?.meeting {
                    details(meeting, at: geo[frame], in: geo.size)
                }
            }
        }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule")
    }

    /// The day's hours in a scroll view of their own, with the system's
    /// scrollers and bounce. They open on the hour before now, and a
    /// meeting's details leave as they scroll.
    private func scrolling<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return ScrollViewReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background { NXPageBackground() }
            }
            .scrollIndicators(.automatic)
            .onScrollPhaseChange { _, phase in
                if phase.isScrolling, hoveredID != nil { hoveredID = nil }
            }
            .onAppear {
                // Once laid out; it's there only with the earlier part shown.
                Task { @MainActor in proxy.scrollTo(NXScheduleGrid.startID, anchor: .top) }
            }
        }
    }

    /// A meeting's details: beside the column, hanging over the tasks, or
    /// under the meeting where the hours span the page.
    private func details(_ meeting: FixedBusyTime, at frame: CGRect, in size: CGSize) -> some View {
        let leading = presentation == .column
        return NXMeetingDetails(meeting: meeting, now: now)
            .frame(width: NXDay.detailsWidth)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: leading ? -(10 + NXDay.detailsWidth)
                        : max(NXDay.gutter, min(frame.minX, size.width - NXDay.detailsWidth)),
                    y: leading ? frame.minY - 4 : frame.maxY + 6)
            .transition(style.slides ? .opacity.combined(with: .offset(x: leading ? 4 : 0, y: leading ? 0 : -4)) : .opacity)
            .allowsHitTesting(false)
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
    /// The hour the day opens on, an hour before now, which the hours scroll
    /// to when they show earlier ones too.
    let start: Int
    let items: [TodaySchedule.Item]
    let now: Date
    /// The meeting under the pointer, whose details the schedule shows.
    @Binding var hoveredID: String?

    /// The hour the day opens on, as the hours' scroll view knows it.
    static let startID = "today.schedule.start"

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
                // Blocks that move, as a replan or a plan moves them, glide
                // there; with Reduce Motion they're simply there.
                .animation(style.slides ? style.ease(320) : nil,
                           value: layout.mapValues { [$0.top, $0.height, Double($0.lane), Double($0.laneCount)] })
            }
            .frame(height: height)
        }
        // Above the start hour's line, room for its label, for the scroll
        // view to open on, below its fade: laid out there, as scrolling to
        // it goes by the frame of the view that has the id.
        .background(alignment: .topLeading) {
            if start > hours.lowerBound {
                VStack(spacing: 0) {
                    Color.clear.frame(width: 1, height: max(0, CGFloat(start - hours.lowerBound) * NXDay.hourHeight
                                                                - NXDay.labelRoom - 1))
                    Color.clear.frame(width: 1, height: 1).id(Self.startID)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, NXDay.labelRoom)
    }

    @ViewBuilder
    private func entry(_ item: TodaySchedule.Item, height: CGFloat, width: CGFloat) -> some View {
        let emphasis: NXScheduleEmphasis = item.isCurrent(at: now) ? .current : schedule.next?.id == item.id ? .next : .none
        if let meeting = item.meeting {
            NXScheduleMeeting(meeting: meeting, height: height, width: width, now: now, emphasis: emphasis)
                .onHover { inside in
                    if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
                }
                .anchorPreference(key: NXMeetingFramesKey.self, value: .bounds) { [item.id: $0] }
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

/// Content scrolling under what stays put above a scroll view fades out over
/// `top` points rather than being cut off; `bottom` fades its foot the same
/// way. Both lie within the room the content leaves at rest, so they show
/// only once it scrolls. `above` puts the top fade just over the scroll
/// view, on content it doesn't clip, and the mask clips the rest.
private struct NXScrollEdgeFade: ViewModifier {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var above = false

    func body(content: Content) -> some View {
        // Always masked, so a fade coming or going never replaces the
        // scroll view and loses its place.
        content.mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: top)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: bottom)
            }
            .padding(.top, above ? -top : 0)
        }
    }
}

/// The pointer rests on the folded schedule's hours while they scroll on
/// their own, so the page holds still for them.
private struct NXHoursHoldPageKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Where each meeting on the hours is, so its details can show over the
/// schedule, out of the hours' scroll view.
private struct NXMeetingFramesKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
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
