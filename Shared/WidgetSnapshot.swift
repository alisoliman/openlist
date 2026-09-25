//
//  WidgetSnapshot.swift
//  Shared between the app and the widget extension.
//

import Foundation

/// A small, read-only view of the user's data, published by the app for the
/// widget to render.
///
/// The widget deliberately does not open the SwiftData store: cross-process
/// Core Data access needs coordination the widget has no reason to take on,
/// and a widget only ever needs a handful of rows. Everything a widget draws,
/// including the day's plan and the work timer, arrives through this file.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning. Missing fields decode to their
    /// defaults, so an older file still renders until the app rewrites it.
    static let currentVersion = 2

    /// One task row.
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        /// The repeat occurrence the row represents. Actions carry it so a
        /// stale tap can never complete the next occurrence of a repeat.
        var occurrenceID: UUID
        var title: String
        var listID: UUID?
        var listName: String
        var listIcon: String
        /// The owning list's colour as 0xRRGGBB.
        var accentHex: UInt32
        var dueDate: Date?
        var includesTime: Bool
        var isCompleted: Bool
        var completedAt: Date?
        var isStarred: Bool
        var hasRepeat: Bool
        /// Raw `TaskPriority`: 0 none, 1 low, 2 medium, 3 high.
        var priority: Int
        var createdAt: Date

        func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
            guard !isCompleted, let dueDate else { return false }
            return includesTime ? dueDate < now : dueDate < calendar.startOfDay(for: now)
        }
    }

    /// One Inbox capture waiting for triage.
    struct InboxItem: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var createdAt: Date
    }

    /// A list the List widget can show, and the configuration picker offers.
    struct ListSummary: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        /// "Parent › Child" for nested lists, otherwise the title.
        var path: String
        var icon: String
        var accentHex: UInt32
        var isInbox: Bool
        var openCount: Int
        var doneCount: Int
        /// Open tasks in the list's own order, capped.
        var openItems: [Item]
        /// Completed tasks, most recent first, capped.
        var doneItems: [Item]
    }

    /// A meeting or a planned task block on the calendar.
    struct AgendaEvent: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable {
            case meeting
            case task
        }

        var id: String
        var kind: Kind
        var title: String
        var start: Date
        var end: Date
        /// Set for task blocks.
        var taskID: UUID?
        var occurrenceID: UUID?
        var listName: String = ""
        var listIcon: String = ""
        /// Task blocks use their list's colour; meetings have none.
        var accentHex: UInt32?
        var isCompleted: Bool = false
        /// The block currently being recorded.
        var isActive: Bool = false
    }

    /// The work session shown in the app's toolbar timer.
    struct Work: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable {
            case working
            case paused
        }

        var state: State
        var taskID: UUID
        var occurrenceID: UUID
        var title: String
        var listName: String
        var listIcon: String
        var accentHex: UInt32
        /// Start of the running segment; `nil` while paused. Absolute values
        /// keep the snapshot unchanged between heartbeats, and let the widget
        /// tick with `Text(timerInterval:)` without reloading.
        var segmentStartedAt: Date?
        /// Time recorded by earlier, closed segments of this occurrence.
        var priorSeconds: Double
        var estimateMinutes: Double
        /// The planned block, when there is one, for the "10:00–11:30" label.
        var blockStart: Date?
        var blockEnd: Date?

        /// Recorded seconds at `now`.
        func elapsed(at now: Date) -> Double {
            priorSeconds + (segmentStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        }

        /// The date the timer counts from, so `Text(timerInterval:)` shows the
        /// full recorded time and not just the running segment.
        var timerOrigin: Date? {
            segmentStartedAt.map { $0.addingTimeInterval(-priorSeconds) }
        }
    }

    /// When an open task due today turns late.
    struct Due: Codable, Equatable, Sendable {
        var date: Date
        var includesTime: Bool

        func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
            includesTime ? date < now : date < calendar.startOfDay(for: now)
        }
    }

    struct ActivityDay: Codable, Equatable, Sendable {
        /// Start of the day in the Mac's time zone.
        var date: Date
        var count: Int
    }

    struct Activity: Codable, Equatable, Sendable {
        /// Oldest first. Starts on a week boundary and ends today, so the last
        /// column is the current week.
        var days: [ActivityDay] = []
        var streak: Int = 0
        var today: Int = 0
        var week: Int = 0
        var month: Int = 0
        /// "September".
        var monthName: String = ""
    }

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date {
        get { stamp.date }
        set { stamp.date = newValue }
    }
    /// Excluded from `==` on purpose: it changes on every build, and the
    /// publisher compares snapshots to decide whether a widget reload is
    /// actually warranted.
    private var stamp = Timestamp(date: .now)

    /// A date that never participates in `==`.
    private nonisolated struct Timestamp: Equatable, Sendable {
        var date: Date
        static func == (lhs: Self, rhs: Self) -> Bool { true }
    }
    /// The library the rows belong to, for building item links.
    var libraryID: UUID?
    /// The app's accent colour as 0xRRGGBB.
    var accentHex: UInt32 = 0x7C4DF0
    /// Mirrors the app's serif-title setting.
    var serifTitles: Bool = true
    /// `Calendar.firstWeekday` the app uses (1 = Sunday … 7 = Saturday).
    var firstWeekday: Int = Calendar.current.firstWeekday

    /// Overdue and due-today work, soonest first.
    var todayItems: [Item] = []
    var overdueCount: Int = 0
    var dueTodayCount: Int = 0
    /// Every open task behind `dueTodayCount`, soonest first and not capped
    /// like `todayItems`, so a widget can move them to late on time.
    var dueToday: [Due] = []
    /// Tomorrow's rows (capped like `todayItems`) and due dates (uncapped), so
    /// a widget can start the new day on time when the app has not run since
    /// midnight to republish.
    var tomorrowItems: [Item] = []
    var dueTomorrow: [Due] = []
    /// Done today exactly as the app's Today counts it: tasks completed today.
    /// A reopen or Undo takes one away; a repeat that rolls forward is open
    /// again, so it is not counted, there or here.
    var completedTodayCount: Int = 0
    var inboxCount: Int = 0
    /// Newest first.
    var inboxItems: [InboxItem] = []
    var totalOpenCount: Int = 0
    /// Active lists in sidebar order, Inbox first.
    var lists: [ListSummary] = []

    /// First day of the week the agenda covers.
    var weekStart: Date?
    /// Meetings and planned blocks from `weekStart` through the end of that
    /// week, sorted by start.
    var agenda: [AgendaEvent] = []
    var work: Work?

    var activity = Activity()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let empty = WidgetSnapshot()
        version = value(.version, 1)
        generatedAt = value(.generatedAt, empty.generatedAt)
        libraryID = value(.libraryID, empty.libraryID)
        accentHex = value(.accentHex, empty.accentHex)
        serifTitles = value(.serifTitles, empty.serifTitles)
        firstWeekday = value(.firstWeekday, empty.firstWeekday)
        todayItems = value(.todayItems, empty.todayItems)
        overdueCount = value(.overdueCount, empty.overdueCount)
        dueTodayCount = value(.dueTodayCount, empty.dueTodayCount)
        dueToday = value(.dueToday, empty.dueToday)
        tomorrowItems = value(.tomorrowItems, empty.tomorrowItems)
        dueTomorrow = value(.dueTomorrow, empty.dueTomorrow)
        completedTodayCount = value(.completedTodayCount, empty.completedTodayCount)
        inboxCount = value(.inboxCount, empty.inboxCount)
        inboxItems = value(.inboxItems, empty.inboxItems)
        totalOpenCount = value(.totalOpenCount, empty.totalOpenCount)
        lists = value(.lists, empty.lists)
        weekStart = value(.weekStart, empty.weekStart)
        agenda = value(.agenda, empty.agenda)
        work = value(.work, empty.work)
        activity = value(.activity, empty.activity)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeIfPresent(libraryID, forKey: .libraryID)
        try container.encode(accentHex, forKey: .accentHex)
        try container.encode(serifTitles, forKey: .serifTitles)
        try container.encode(firstWeekday, forKey: .firstWeekday)
        try container.encode(todayItems, forKey: .todayItems)
        try container.encode(overdueCount, forKey: .overdueCount)
        try container.encode(dueTodayCount, forKey: .dueTodayCount)
        try container.encode(dueToday, forKey: .dueToday)
        try container.encode(tomorrowItems, forKey: .tomorrowItems)
        try container.encode(dueTomorrow, forKey: .dueTomorrow)
        try container.encode(completedTodayCount, forKey: .completedTodayCount)
        try container.encode(inboxCount, forKey: .inboxCount)
        try container.encode(inboxItems, forKey: .inboxItems)
        try container.encode(totalOpenCount, forKey: .totalOpenCount)
        try container.encode(lists, forKey: .lists)
        try container.encodeIfPresent(weekStart, forKey: .weekStart)
        try container.encode(agenda, forKey: .agenda)
        try container.encodeIfPresent(work, forKey: .work)
        try container.encode(activity, forKey: .activity)
    }

    private enum CodingKeys: String, CodingKey {
        case version, generatedAt
        case libraryID, accentHex, serifTitles, firstWeekday
        case todayItems, overdueCount, dueTodayCount, dueToday, tomorrowItems, dueTomorrow, completedTodayCount
        case inboxCount, inboxItems, totalOpenCount, lists
        case weekStart, agenda, work, activity
    }

    /// The list a List widget shows: the chosen one, or the first real list.
    func list(id: UUID?) -> ListSummary? {
        if let id, let list = lists.first(where: { $0.id == id }) { return list }
        return lists.first { !$0.isInbox } ?? lists.first
    }
}

/// Reads and writes the snapshot file in the shared container.
nonisolated enum WidgetSnapshotStore {
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = AppGroup.snapshotURL, let data = try? encode(snapshot) else { return }
        // Atomic so the widget never reads a half-written file.
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = AppGroup.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}
