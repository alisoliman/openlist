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
/// and a widget only ever needs a handful of rows.
///
/// Every date is absolute. The widget works out "late", "Tomorrow", ages, the
/// Agenda's now line and the heatmap's columns against each timeline entry's
/// own date, so entries after midnight or a quarter of an hour later stay right
/// while the app isn't running.
///
/// Version 2 is a superset of version 1: keys keep their meaning and version 1's
/// are all still written, so a version 1 widget reads a new file, and every key
/// decodes when present, so a file written by an older app still renders.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 2

    /// A task row.
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        /// The occurrence a completion applies to; nil in version 1 files.
        var occurrenceID: UUID?
        var title: String
        var listID: UUID?
        var listName: String
        var listIcon: String
        /// Raw value of `ListAccent`.
        var accent: String
        var dueDate: Date?
        var includesTime: Bool
        var isCompleted: Bool
        var completedAt: Date?
        var isStarred: Bool
        var hasRepeat: Bool
        /// Raw value of `TaskPriority`.
        var priority: Int = 0
    }

    /// How many open tasks fall due on one day: enough to count overdue and
    /// due-today work at any entry date, in as many entries as there are days
    /// with something due, however many tasks share them.
    struct DueDay: Codable, Equatable, Sendable {
        /// The day's start.
        var day: Date
        var count: Int
    }

    struct InboxItem: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var createdAt: Date
    }

    struct ListSummary: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var icon: String
        var accent: String
        var openCount: Int
        var doneCount: Int
        /// The first open tasks in the list's own order.
        var openItems: [Item] = []
        /// The latest completions, newest first.
        var doneItems: [Item] = []
    }

    /// The work on the toolbar's timer: running, or paused and resumable.
    struct Work: Codable, Equatable, Sendable {
        var taskID: UUID
        var occurrenceID: UUID
        var title: String
        var listName: String
        var listIcon: String
        var accent: String
        var isRunning: Bool
        /// Running: when the elapsed clock would read zero, so it stays put
        /// while the work runs. Paused: unused.
        var elapsedAnchor: Date
        /// Paused: the seconds recorded on this occurrence. Running: zero.
        var pausedElapsed: Double
        /// The slot the work fills on the calendar, if it has one.
        var slotStart: Date?
        var slotEnd: Date?
        var estimateMinutes: Double
    }

    struct AgendaItem: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case meeting, task }
        var id: String
        var kind: Kind
        var title: String
        var start: Date
        var end: Date
        var taskID: UUID?
        var occurrenceID: UUID?
        var listIcon: String?
        var listName: String?
        var accent: String?
        var isCompleted: Bool
        var isActive: Bool
        /// A slot the plan suggests but nobody placed. Up Next can offer it;
        /// the Agenda, like the app's calendar, doesn't draw it.
        var isFlexible: Bool
    }

    struct AgendaDay: Codable, Equatable, Sendable {
        var day: Date
        var items: [AgendaItem]
    }

    /// Completions per day for the heatmap.
    struct Activity: Codable, Equatable, Sendable {
        /// The first day `counts` covers.
        var start: Date
        /// One count per day from `start` to the day the snapshot was built.
        var counts: [Int]
    }

    var version = Self.currentVersion
    /// Excluded from `==` on purpose: it changes on every build, and the
    /// publisher compares snapshots to decide whether a widget reload is
    /// actually warranted.
    var generatedAt: Date = .now
    /// Rewritten, without a reload, while work runs. A running timer whose
    /// heartbeat has stopped belongs to an app that is no longer running.
    var heartbeatAt: Date?
    /// Builds task and list links.
    var libraryID: UUID?
    /// `Calendar.firstWeekday` from the app's settings.
    var firstWeekday = 1
    /// Open tasks due before the end of tomorrow, overdue ones included.
    var todayItems: [Item] = []
    /// Every open, dated task, by the day it's due, soonest first.
    var dueDays: [DueDay] = []
    /// Version 1's counts, worked out as it did when the snapshot was built,
    /// for a version 1 widget still reading the file. This one counts from
    /// `dueDays` at each entry's date, so `==` leaves these out.
    var overdueCount = 0
    var dueTodayCount = 0
    var completedTodayCount = 0
    /// The day `completedTodayCount` belongs to.
    var completedTodayDay: Date?
    var inboxCount = 0
    /// The newest open Inbox tasks.
    var inboxItems: [InboxItem] = []
    var totalOpenCount = 0
    /// Active lists other than Inbox, in sidebar order.
    var lists: [ListSummary] = []
    var work: Work?
    /// Each day of the settings week, and tomorrow when the week ends today.
    var agenda: [AgendaDay] = []
    var activity: Activity?

    init() {}

    static func == (lhs: WidgetSnapshot, rhs: WidgetSnapshot) -> Bool {
        lhs.version == rhs.version
            && lhs.libraryID == rhs.libraryID
            && lhs.firstWeekday == rhs.firstWeekday
            && lhs.todayItems == rhs.todayItems
            && lhs.dueDays == rhs.dueDays
            && lhs.completedTodayCount == rhs.completedTodayCount
            && lhs.completedTodayDay == rhs.completedTodayDay
            && lhs.inboxCount == rhs.inboxCount
            && lhs.inboxItems == rhs.inboxItems
            && lhs.totalOpenCount == rhs.totalOpenCount
            && lhs.lists == rhs.lists
            && lhs.work == rhs.work
            && lhs.agenda == rhs.agenda
            && lhs.activity == rhs.activity
    }

    /// Open tasks' due dates, counted by day, soonest first.
    static func dueDays(_ dates: some Sequence<Date>, calendar: Calendar) -> [DueDay] {
        var counts: [Date: Int] = [:]
        for date in dates { counts[calendar.startOfDay(for: date), default: 0] += 1 }
        return counts.map { DueDay(day: $0.key, count: $0.value) }.sorted { $0.day < $1.day }
    }

    /// Counts `change` more open tasks due on `date`'s day, or fewer.
    mutating func countDue(on date: Date, by change: Int, calendar: Calendar) {
        let day = calendar.startOfDay(for: date)
        if let index = dueDays.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
            dueDays[index].count += change
            if dueDays[index].count <= 0 { dueDays.remove(at: index) }
        } else if change > 0 {
            dueDays.append(DueDay(day: day, count: change))
            dueDays.sort { $0.day < $1.day }
        }
    }

    private static func legacyDueDays(overdue: Int, dueToday: Int, builtAt date: Date) -> [DueDay] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let before = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        return [DueDay(day: before, count: overdue), DueDay(day: day, count: dueToday)].filter { $0.count > 0 }
    }
}

// MARK: - Decoding older files

// Synthesized decoding would throw on the first key a version 1 file lacks, so
// every key decodes when present and falls back to its default otherwise.

nonisolated private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

nonisolated extension WidgetSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // A file without a version was written by version 1.
        version = c.value(.version, or: 1)
        generatedAt = c.value(.generatedAt, or: .now)
        heartbeatAt = c.value(.heartbeatAt, or: nil)
        libraryID = c.value(.libraryID, or: nil)
        firstWeekday = c.value(.firstWeekday, or: 1)
        todayItems = c.value(.todayItems, or: [])
        overdueCount = c.value(.overdueCount, or: 0)
        dueTodayCount = c.value(.dueTodayCount, or: 0)
        // Version 1 wrote its counts instead: late the day before it was
        // built, due that day, so they read as they did until the app
        // publishes again.
        dueDays = c.contains(.dueDays) ? c.value(.dueDays, or: [])
            : Self.legacyDueDays(overdue: overdueCount, dueToday: dueTodayCount, builtAt: generatedAt)
        completedTodayCount = c.value(.completedTodayCount, or: 0)
        completedTodayDay = c.value(.completedTodayDay, or: nil)
        inboxCount = c.value(.inboxCount, or: 0)
        inboxItems = c.value(.inboxItems, or: [])
        totalOpenCount = c.value(.totalOpenCount, or: 0)
        lists = c.value(.lists, or: [])
        work = c.value(.work, or: nil)
        agenda = c.value(.agenda, or: [])
        activity = c.value(.activity, or: nil)
    }
}

nonisolated extension WidgetSnapshot.Item {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  occurrenceID: c.value(.occurrenceID, or: nil),
                  title: c.value(.title, or: ""),
                  listID: c.value(.listID, or: nil),
                  listName: c.value(.listName, or: ""),
                  listIcon: c.value(.listIcon, or: ""),
                  accent: c.value(.accent, or: "graphite"),
                  dueDate: c.value(.dueDate, or: nil),
                  includesTime: c.value(.includesTime, or: false),
                  isCompleted: c.value(.isCompleted, or: false),
                  completedAt: c.value(.completedAt, or: nil),
                  isStarred: c.value(.isStarred, or: false),
                  hasRepeat: c.value(.hasRepeat, or: false),
                  priority: c.value(.priority, or: 0))
    }
}

nonisolated extension WidgetSnapshot.ListSummary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  title: c.value(.title, or: ""),
                  icon: c.value(.icon, or: ""),
                  accent: c.value(.accent, or: "graphite"),
                  openCount: c.value(.openCount, or: 0),
                  doneCount: c.value(.doneCount, or: 0),
                  openItems: c.value(.openItems, or: []),
                  doneItems: c.value(.doneItems, or: []))
    }
}

/// Reads and writes the snapshot file in the shared container.
nonisolated enum WidgetSnapshotStore {
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = AppGroup.snapshotURL, let data = encode(snapshot) else { return }
        // Atomic so the widget never reads a half-written file.
        try? data.write(to: url, options: .atomic)
    }

    /// The published snapshot, or nil when there is none yet or a newer app
    /// wrote one this widget can't be sure it reads correctly.
    static func read() -> WidgetSnapshot? {
        guard let url = AppGroup.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version <= WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }
}
