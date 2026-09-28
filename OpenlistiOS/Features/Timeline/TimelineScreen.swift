//
//  TimelineScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Today as a timeline (mockup 03), in Today's place: the week strip, and the
/// picked day's schedule on the whole day's hour grid, as the calendar draws
/// it: done blocks, the work on now, planned slots as long as they run,
/// meetings, and tasks due at a time with no slot. The grid scrolls in its
/// card, from an hour before now. "N to plan" fits the day's tasks that have
/// no place on it into free time; each of them is also in a row above the
/// card, to hold and drop at a time of its own, and a planned block drops at
/// another time the same way.
struct TimelineScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            TimelinePage(now: env.now)
        }
    }
}

private struct TimelinePage: View {
    let now: Date
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var planning = TimelinePlanning()

    var body: some View {
        // At accessibility sizes the page scrolls, and the card is a fixed
        // window onto the day, rather than a sliver under the header.
        let fills = !typeSize.isAccessibilitySize
        let navigator = env.navigator
        let calendar = env.settings.calendar
        let today = calendar.startOfDay(for: now)
        let day = navigator.timelineDay.map { calendar.startOfDay(for: $0) } ?? today
        let schedule = TimelineSchedule(env: env, library: library, day: day, now: now)
        OLScreen(identifier: PhoneRoute.timeline.screenIdentifier, scrolls: !fills) {
            OLTopBar {
                OLEyebrow(OLFormat.eyebrowDate(now, calendar: calendar))
            } trailing: {
                OLViewToggle(selection: .calendar, from: navigator.todaySwitchedFrom == .list ? .list : nil,
                             listIdentifier: "timeline.list", arrived: { _ = navigator.takeTodaySwitch() }) { _ in
                    navigator.open(.today)
                }
            }
        } content: {
            OLHeader("Today")
            OLWeekStrip(days: OLWeekStrip.week(containing: day, calendar: calendar),
                        selection: Binding(get: { day },
                                           set: { navigator.timelineDay = calendar.isDate($0, inSameDayAs: today) ? nil : $0 }),
                        today: now, calendar: calendar)
                .padding(.top, 14)
            OLGroup(schedule.title) {
                if day == today, !schedule.toPlan.isEmpty {
                    OLGroupAction("\(schedule.toPlan.count) to plan") { env.actions.fit(schedule.toPlan) }
                        .accessibilityIdentifier("timeline.toPlan")
                }
            } content: {
                if !schedule.toPlan.isEmpty {
                    PlanRow(tasks: schedule.toPlan, planning: planning, canFit: day == today)
                }
                TimelineCard(schedule: schedule, day: day, now: now, planning: planning) { open($0) }
                    .frame(height: fills ? nil : 560)
                    .frame(maxHeight: fills ? .infinity : nil)
            }
            .frame(maxHeight: fills ? .infinity : nil, alignment: .top)
        }
    }

    private func open(_ item: OLTimelineItem) {
        guard let taskID = item.taskID else { return }
        env.navigator.open(item.kind == .working ? .working : .taskDetail(taskID))
    }
}

// MARK: - Planning by drag

/// A task lifted to plan, carried on its own type inside the app only, so
/// no other app or text field reads it.
enum PlanDrag {
    static let type = UTType(exportedAs: "app.openlist.plan-drag")

    static func provider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { load in
            load(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

/// The drag in hand over the timeline: what was lifted, where it would
/// land, and the card's scrolling, which runs on its own while the finger
/// rests near the card's top or bottom edge.
@MainActor @Observable
final class TimelinePlanning {
    struct Lifted: Equatable {
        var id: UUID
        var title: String
        var minutes: Int
        /// The slot being moved, when a block was lifted.
        var placementID: UUID?
    }

    var lifted: Lifted?
    /// Where the lifted task would start, while it is over the card and
    /// fits there.
    private(set) var landing: Date?
    var position = ScrollPosition(y: 0)
    @ObservationIgnored var offset: CGFloat = 0
    @ObservationIgnored var viewport: CGFloat = 0
    @ObservationIgnored var contentHeight: CGFloat = 0
    /// The day the card last opened on, so coming back from a task keeps
    /// where it was scrolled.
    @ObservationIgnored var scrolledDay: Date?
    @ObservationIgnored private var fingerY: CGFloat?
    @ObservationIgnored private var landingAt: ((CGFloat) -> Date?)?
    @ObservationIgnored private var speed: CGFloat = 0
    @ObservationIgnored private var scroller: Task<Void, Never>?

    /// Within this of the card's top or bottom, the grid scrolls, faster
    /// nearer the edge.
    static let edge: CGFloat = 56
    static let fastest: CGFloat = 12

    func lift(_ task: Block, minutes: Int, placementID: UUID? = nil) {
        lifted = Lifted(id: task.id, title: task.displayTitle, minutes: minutes, placementID: placementID)
        land(nil)
    }

    /// The finger at `y` in the card; `start` maps a y in the grid's content
    /// to the start a drop there gives, nil where it can't go. Returns
    /// whether a drop there lands.
    @discardableResult
    func hover(at y: CGFloat, start: @escaping (CGFloat) -> Date?) -> Bool {
        fingerY = y
        landingAt = start
        land(start(y + offset))
        speed = Self.speed(at: y, viewport: viewport)
        if speed != 0, scroller == nil { scrollWhileNearAnEdge() }
        return landing != nil
    }

    func leave() {
        land(nil)
        fingerY = nil
        speed = 0
        scroller?.cancel()
        scroller = nil
    }

    func end() {
        leave()
        lifted = nil
    }

    func scroll(toHour hour: Int, hourHeight: CGFloat) {
        position.scrollTo(y: CGFloat(max(0, hour)) * hourHeight)
    }

    static func speed(at y: CGFloat, viewport: CGFloat) -> CGFloat {
        guard viewport > edge * 2 else { return 0 }
        if y < edge { return -fastest * (edge - max(0, y)) / edge }
        if y > viewport - edge { return fastest * (min(viewport, y) - (viewport - edge)) / edge }
        return 0
    }

    /// Only a change redraws the ghost.
    private func land(_ start: Date?) {
        if landing != start { landing = start }
    }

    private func scrollWhileNearAnEdge() {
        scroller = Task { [weak self] in
            // Held only for each frame's step, never across the wait.
            while !Task.isCancelled, self?.scrollStep() == true {
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { self?.scroller = nil }
        }
    }

    /// One frame's scroll; false once the finger leaves the edges or the
    /// drag ends.
    private func scrollStep() -> Bool {
        guard speed != 0, lifted != nil else { return false }
        let next = min(max(0, contentHeight - viewport), max(0, offset + speed))
        if next != offset {
            offset = next
            position.scrollTo(y: next)
            if let y = fingerY, let start = landingAt { land(start(y + next)) }
        }
        return true
    }

    /// The start a drop `y` points into the grid gives: the nearest quarter
    /// hour, early enough for `minutes` to end by midnight, and on today
    /// the next quarter hour from now at the earliest. Nil where that
    /// can't be: a day gone, or too late today for it to fit.
    static func start(atContentY y: CGFloat, day: Date, minutes: Int, now: Date, hourHeight: CGFloat,
                      calendar: Calendar) -> Date? {
        let latest = 24 * 60 - minutes
        guard latest >= 0 else { return nil }
        let raw = Double(max(0, y - OLTimeline.inset)) / Double(hourHeight) * 60
        let quarter = min(Int((raw / 15).rounded()) * 15, latest / 15 * 15)
        guard let start = calendar.date(bySettingHour: quarter / 60, minute: quarter % 60, second: 0, of: day) else { return nil }
        guard start < now else { return start }
        guard calendar.isDate(now, inSameDayAs: day) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let next = ((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / 15 * 15 + 15
        guard next <= latest else { return nil }
        return calendar.date(bySettingHour: next / 60, minute: next % 60, second: 0, of: day)
    }
}

/// The picked day's tasks with no place on it, to hold and drop on the
/// timeline; a tap opens one.
private struct PlanRow: View {
    let tasks: [Block]
    let planning: TimelinePlanning
    /// "Find a slot" searches from now, so only today's row offers it.
    let canFit: Bool
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hold a task and drag it onto the timeline.")
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .padding(.horizontal, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tasks) { task in chip(task) }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .padding(.bottom, 4)
    }

    private func chip(_ task: Block) -> some View {
        let minutes = env.actions.planMinutes(for: task)
        return Button { env.navigator.open(.taskDetail(task.id)) } label: {
            PlanChip(title: task.displayTitle, minutes: minutes)
        }
        .buttonStyle(OLPressStyle(scale: 0.96))
        .onDrag {
            planning.lift(task, minutes: minutes)
            return PlanDrag.provider(for: task.id)
        } preview: {
            PlanChip(title: task.displayTitle, minutes: minutes)
        }
        .accessibilityLabel("\(task.displayTitle), \(minutes) min")
        .accessibilityHint("Drag onto the timeline to plan it at a time")
        .accessibilityActions {
            if canFit { Button("Find a slot") { env.actions.fit([task]) } }
        }
        .accessibilityIdentifier("plan.chip")
    }
}

private struct PlanChip: View {
    let title: String
    let minutes: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(OL.ink).lineLimit(1)
            Text("\(minutes)m").foregroundStyle(OL.accentText).monospacedDigit()
        }
        .font(OLFont.chipSmall)
        .padding(.horizontal, 12)
        .frame(maxWidth: 240, minHeight: 34)
        .fixedSize(horizontal: true, vertical: false)
        .background { Capsule(style: .continuous).fill(OL.surface).olShadow(.card) }
        .contentShape(.capsule)
    }
}

/// The day's hour grid in its card, 00:00 to 24:00, scrolled to an hour
/// before now (or the day's first block), where a lifted task drops at the
/// quarter hour under the finger.
private struct TimelineCard: View {
    let schedule: TimelineSchedule
    let day: Date
    let now: Date
    let planning: TimelinePlanning
    let open: (OLTimelineItem) -> Void
    @Environment(PhoneEnvironment.self) private var env

    private let hourHeight: CGFloat = 44

    var body: some View {
        @Bindable var planning = planning
        let calendar = env.settings.calendar
        let today = calendar.startOfDay(for: now)
        let takesDrops = day >= today
        ScrollView {
            OLTimeline(items: schedule.items, hours: schedule.hours, now: day == today ? now : nil,
                       hourHeight: hourHeight, calendar: calendar, day: day, ghost: ghost(calendar: calendar),
                       dragging: planning.landing == nil ? nil : planning.lifted?.id,
                       drag: takesDrops ? { lift($0) } : nil, nudge: takesDrops ? { nudge($0, by: $1) } : nil,
                       open: open)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($planning.position)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
            planning.offset = geometry.contentOffset.y
            planning.viewport = geometry.containerSize.height
            planning.contentHeight = geometry.contentSize.height
        }
        .olCard()
        .onDrop(of: [PlanDrag.type], delegate: TimelineDrop(
            takesDrops: takesDrops,
            hover: { point in
                guard let lifted = planning.lifted else { return false }
                let minutes = lifted.minutes
                return planning.hover(at: point.y) { y in
                    TimelinePlanning.start(atContentY: y, day: day, minutes: minutes, now: env.now,
                                           hourHeight: hourHeight, calendar: calendar)
                }
            },
            leave: { planning.leave() },
            drop: { drop(at: $0, providers: $1) }))
        .onAppear { openOnDay() }
        .onChange(of: day) { openOnDay() }
        .onDisappear { planning.end() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.card")
    }

    private func ghost(calendar: Calendar) -> OLTimelineItem? {
        guard let lifted = planning.lifted, let start = planning.landing else { return nil }
        return OLTimelineItem(id: "landing", kind: .planned, title: lifted.title, start: start,
                              end: start.addingTimeInterval(TimeInterval(lifted.minutes * 60)),
                              detail: CompactText.clock(start, calendar: calendar))
    }

    /// Opens a day an hour before now, or before its first block, once:
    /// coming back from a task keeps where it was scrolled.
    private func openOnDay() {
        guard planning.scrolledDay != day else { return }
        planning.scrolledDay = day
        planning.scroll(toHour: schedule.scrollHour, hourHeight: hourHeight)
    }

    /// A block lifts as its slot, keeping its length; a due time as the
    /// task, for its estimate.
    private func lift(_ item: OLTimelineItem) -> NSItemProvider {
        guard let id = item.taskID, let task = env.store.block(id: id) else { return NSItemProvider() }
        let minutes = item.placementID != nil
            ? max(5, Int((item.end.timeIntervalSince(item.start) / 60).rounded())) : env.actions.planMinutes(for: task)
        planning.lift(task, minutes: minutes, placementID: item.placementID)
        return PlanDrag.provider(for: id)
    }

    private func nudge(_ item: OLTimelineItem, by minutes: Int) {
        guard let id = item.taskID, let task = env.store.block(id: id) else { return }
        env.actions.place(task, at: item.start.addingTimeInterval(TimeInterval(minutes * 60)), placementID: item.placementID)
    }

    /// Places the lifted task where it was shown landing, else at the
    /// drop's point; a drag this card never saw lift carries its task's ID.
    private func drop(at point: CGPoint, providers: [NSItemProvider]) -> Bool {
        let landing = planning.landing
        let lifted = planning.lifted
        planning.end()
        let env = env, day = day, hourHeight = hourHeight, y = point.y + planning.offset
        if let lifted {
            return Self.place(lifted.id, placementID: lifted.placementID, at: landing, contentY: y, day: day,
                              hourHeight: hourHeight, env: env)
        }
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: PlanDrag.type.identifier) { data, _ in
            guard let data, let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { return }
            Task { @MainActor in
                _ = Self.place(id, placementID: nil, at: nil, contentY: y, day: day, hourHeight: hourHeight, env: env)
            }
        }
        return true
    }

    private static func place(_ id: UUID, placementID: UUID?, at landing: Date?, contentY y: CGFloat, day: Date,
                              hourHeight: CGFloat, env: PhoneEnvironment) -> Bool {
        guard let task = env.store.block(id: id),
              let start = landing ?? TimelinePlanning.start(atContentY: y, day: day, minutes: env.actions.planMinutes(for: task),
                                                            now: env.now, hourHeight: hourHeight,
                                                            calendar: env.settings.calendar)
        else { return false }
        return env.actions.place(task, at: start, placementID: placementID)
    }
}

@MainActor
private struct TimelineDrop: DropDelegate {
    let takesDrops: Bool
    /// Whether a drop at that point lands.
    let hover: (CGPoint) -> Bool
    let leave: () -> Void
    let drop: (CGPoint, [NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool { takesDrops && info.hasItemsConforming(to: [PlanDrag.type]) }
    func dropEntered(info: DropInfo) { _ = hover(info.location) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: hover(info.location) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) { leave() }
    func performDrop(info: DropInfo) -> Bool { drop(info.location, info.itemProviders(for: [PlanDrag.type])) }
}

/// The picked day as the timeline draws it.
@MainActor
struct TimelineSchedule {
    var items: [OLTimelineItem] = []
    /// The whole day.
    var hours: ClosedRange<Int> = 0...24
    /// The hour the card opens on: one before now today, else one before
    /// the day's first block, else 08:00.
    var scrollHour = 8
    /// The day's tasks with no place on it: no slot and no time to be due at.
    var toPlan: [Block] = []
    var title = "Schedule"

    init(env: PhoneEnvironment, library: NextLibrary, day: Date, now: Date) {
        let dates = env.settings.calendar
        let coordinator = env.calendar
        let isToday = dates.isDate(day, inSameDayAs: now)
        guard let next = dates.date(byAdding: .day, value: 1, to: day) else { return }
        let span = DateInterval(start: day, end: next)
        if !isToday { title = CompactText.day(day, now: now, calendar: dates) }
        let work = PhoneWork(env: env, now: now)

        var slotted: Set<UUID> = []
        for block in coordinator.visibleBlocks where block.end > span.start && block.start < span.end {
            let task = env.store.block(id: block.taskID)
            let title = task?.displayTitle ?? block.titleSnapshot ?? "Task"
            let done = block.isCompleted || task?.isCompleted == true || env.actions.isClosing(block.taskID)
            let kind: OLTimelineItem.Kind
            var detail: String?
            if done {
                kind = .done
            } else if block.isActive || block.id == coordinator.pausedBlockID {
                kind = .working
                detail = "\(work.state == .paused ? "Paused" : "Now") · \(work.leftText)"
            } else {
                kind = .planned
                detail = "\(Int(block.durationMinutes.rounded()))m"
            }
            if !done { slotted.insert(block.taskID) }
            // A slot across midnight draws its part of this day. The work in
            // hand's slots stay put while it runs or waits to resume.
            items.append(OLTimelineItem(id: block.id, kind: kind, title: title,
                                        start: max(block.start, span.start), end: min(block.end, span.end),
                                        detail: detail, taskID: block.taskID, placementID: block.placementID,
                                        movable: kind == .planned && block.taskID != work.task?.id))
        }
        for meeting in coordinator.externalCalendars.busyTimes(in: span) where meeting.end.timeIntervalSince(meeting.start) < 20 * 3600 {
            items.append(OLTimelineItem(id: "event-\(meeting.id)", kind: .event, title: meeting.title,
                                        start: max(meeting.start, span.start), end: min(meeting.end, span.end),
                                        detail: "Calendar event"))
        }
        // Due at a time that day, with no slot of its own.
        for task in library.open where task.includesTime && !slotted.contains(task.id) {
            guard let due = task.dueDate, span.contains(due), !env.actions.isClosing(task.id) else { continue }
            items.append(OLTimelineItem(id: "due-\(task.id)", kind: .due, title: task.displayTitle, start: due, end: due,
                                        taskID: task.id, movable: task.id != work.task?.id))
            slotted.insert(task.id)
        }
        items.sort { $0.start < $1.start }

        if isToday {
            // In Today's order, most late first, the same on every launch.
            let tasks = library.open.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            let agenda = TodayAgenda(tasks: tasks, closing: env.actions.closing, now: now, calendar: dates, order: .schedule)
            toPlan = agenda.scheduled.filter { !slotted.contains($0.id) && !$0.includesTime && $0.id != work.task?.id }
            scrollHour = dates.component(.hour, from: now) - 1
        } else {
            // A later day's: what falls due that day, with no slot yet.
            if day > now {
                toPlan = library.open.filter { task in
                    guard let due = task.dueDate, span.contains(due) else { return false }
                    return !task.includesTime && !slotted.contains(task.id) && !env.actions.isClosing(task.id)
                }
            }
            scrollHour = (items.map { dates.component(.hour, from: $0.start) }.min() ?? 9) - 1
        }
        scrollHour = min(16, max(0, scrollHour))
    }
}
