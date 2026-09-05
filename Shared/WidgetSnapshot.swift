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
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var listName: String
        var listIcon: String
        /// Raw value of `ListAccent`.
        var accent: String
        var dueDate: Date?
        var includesTime: Bool
        var isCompleted: Bool
        var isStarred: Bool
        var hasRepeat: Bool

        var isOverdue: Bool {
            guard !isCompleted, let dueDate else { return false }
            return includesTime ? dueDate < .now : dueDate < Calendar.current.startOfDay(for: .now)
        }

        /// "Today", "9:30", "Tue" — the compact form a widget row can afford.
        ///
        /// Mirrors the app's own relative wording (including the weekday name
        /// within a week) so the same task does not read "Fri" in the app and
        /// "12 Sep" in the widget. The rule is duplicated rather than shared
        /// because the app-side helper lives on `Store`, which the extension
        /// cannot see.
        var dueText: String {
            guard let dueDate else { return "" }
            let calendar = Calendar.current

            if includesTime, calendar.isDateInToday(dueDate) {
                return dueDate.formatted(date: .omitted, time: .shortened)
            }
            if calendar.isDateInToday(dueDate) { return "Today" }
            if calendar.isDateInYesterday(dueDate) { return "Yesterday" }
            if calendar.isDateInTomorrow(dueDate) { return "Tomorrow" }

            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: .now),
                to: calendar.startOfDay(for: dueDate)
            ).day ?? 0
            if abs(days) < 7 {
                return dueDate.formatted(.dateTime.weekday(.abbreviated))
            }
            return dueDate.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    struct ListSummary: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var icon: String
        var accent: String
        var openCount: Int
        var doneCount: Int
    }

    /// Excluded from `==` on purpose: it changes on every build, and the
    /// publisher compares snapshots to decide whether a widget reload is
    /// actually warranted.
    var generatedAt: Date = .now
    /// Overdue and due-today work, soonest first.
    var todayItems: [Item] = []
    var overdueCount: Int = 0
    var dueTodayCount: Int = 0
    var completedTodayCount: Int = 0
    var inboxCount: Int = 0
    var totalOpenCount: Int = 0
    var lists: [ListSummary] = []

    static func == (lhs: WidgetSnapshot, rhs: WidgetSnapshot) -> Bool {
        lhs.todayItems == rhs.todayItems
            && lhs.overdueCount == rhs.overdueCount
            && lhs.dueTodayCount == rhs.dueTodayCount
            && lhs.completedTodayCount == rhs.completedTodayCount
            && lhs.inboxCount == rhs.inboxCount
            && lhs.totalOpenCount == rhs.totalOpenCount
            && lhs.lists == rhs.lists
    }

    /// Shown in the widget gallery and while real data loads.
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            todayItems: [
                Item(
                    id: UUID(),
                    title: "Pay the electricity bill",
                    listName: "Personal",
                    listIcon: "🌱",
                    accent: "green",
                    dueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
                    includesTime: false,
                    isCompleted: false,
                    isStarred: false,
                    hasRepeat: true
                ),
                Item(
                    id: UUID(),
                    title: "Call Mum",
                    listName: "Personal",
                    listIcon: "🌱",
                    accent: "green",
                    dueDate: .now,
                    includesTime: true,
                    isCompleted: false,
                    isStarred: true,
                    hasRepeat: false
                ),
                Item(
                    id: UUID(),
                    title: "Book the Hakone ryokan",
                    listName: "Japan trip",
                    listIcon: "🗻",
                    accent: "indigo",
                    dueDate: .now,
                    includesTime: false,
                    isCompleted: false,
                    isStarred: false,
                    hasRepeat: false
                ),
            ],
            overdueCount: 1,
            dueTodayCount: 2,
            completedTodayCount: 3,
            inboxCount: 2,
            totalOpenCount: 9,
            lists: [
                ListSummary(id: UUID(), title: "Personal", icon: "🌱", accent: "green", openCount: 4, doneCount: 2),
                ListSummary(id: UUID(), title: "Japan trip", icon: "🗻", accent: "indigo", openCount: 3, doneCount: 1),
            ]
        )
    }
}

/// Reads and writes the snapshot file in the shared container.
nonisolated enum WidgetSnapshotStore {
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = AppGroup.snapshotURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        // Atomic so the widget never reads a half-written file.
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard
            let url = AppGroup.snapshotURL,
            let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
