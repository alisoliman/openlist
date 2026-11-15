//
//  PhoneTaskRow.swift
//  OpenlistiOS
//

import SwiftUI

/// Where a task's row is drawn, which decides the one value at its end: Today
/// leaves out what Today already says, Select only the dates.
enum PhoneRowContext: Equatable {
    /// Today: "3d late", "11:30", a repeat's glyph, a starred task's "1 of 3".
    case today
    /// A list's page and Find: dates with a repeat's glyph, or a star.
    case list
    /// Select: the date words alone.
    case select
}

/// A task as a card row (`OLTaskRow`): its checkbox ticks through
/// `PhoneActions`, so it dwells with Undo, its date offers other days, and
/// the rest opens Task detail. Long-pressing offers the task's quick actions.
struct PhoneTaskRow: View {
    let task: Block
    var context: PhoneRowContext = .list
    var depth = 0
    var subtitle: String?
    var separator: OLSeparator = .none
    /// Where the task sits on the day displayed by Today's agenda.
    var slot: Date?
    var agendaDay: Date?
    /// The parent may place a due-today subtask outside its original Today group.
    var showsDueToday = false
    /// A starred task's subtasks, done and all, for Today's "1 of 3".
    var subtasks: (done: Int, total: Int)?
    var emphasizesTitle = false
    /// Whether a done task says when it was done: in a fold, not where it
    /// was ticked among open ones.
    var showsCompletion = true
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let actions = env.actions
        let closing = actions.isClosing(task.id)
        let trailing = task.isCompleted && !closing && !showsCompletion ? nil
            : Self.trailing(for: task, closing: closing, context: context, slot: slot, agendaDay: agendaDay, subtasks: subtasks,
                            showsDueToday: showsDueToday, now: env.now, calendar: env.settings.calendar)
        let source = subtitle == nil || context == .today ? nil : library.list(task.listID)
        OLTaskRow(title: task.displayTitle,
                  state: Self.check(for: task, closing: closing, now: env.now, calendar: env.settings.calendar),
                  depth: depth, subtitle: subtitle,
                  subtitleIcon: source?.icon,
                  subtitleAccent: source?.accent.color ?? OL.muted,
                  emphasizesTitle: emphasizesTitle || context == .today,
                  trailing: trailing,
                  separator: separator,
                  onToggle: { actions.toggle(task) },
                  onOpen: { env.navigator.open(.taskDetail(task.id)) },
                  trailingControl: Self.dueMenu(for: task, trailing: trailing, closing: closing))
            .contextMenu { PhoneTaskMenu(task: task) }
            .phoneTaskSwipe(task)
    }

    /// The menu that changes an open task's date from its row, where the row
    /// shows that date. Not while it dwells: ticked, it's on its way out.
    static func dueMenu(for task: Block, trailing: OLTrailing?, closing: Bool) -> PhoneDueMenu? {
        guard let trailing, trailing.isDue, !closing, !task.isCompleted else { return nil }
        return PhoneDueMenu(task: task, trailing: trailing)
    }

    /// Done while it dwells or once written; late ahead of priority, as in
    /// the widgets and the Mac's rows.
    static func check(for task: Block, closing: Bool, now: Date, calendar: Calendar) -> OLCheck {
        if closing || task.isCompleted { return .done }
        if let due = task.dueDate, CompactText.dayOffset(from: now, to: due, calendar: calendar) < 0 { return .late }
        return task.priority == .none ? .open : .priority(task.priority)
    }

    static func trailing(for task: Block, closing: Bool = false, context: PhoneRowContext, slot: Date? = nil,
                         agendaDay: Date? = nil, subtasks: (done: Int, total: Int)? = nil, showsDueToday: Bool = false,
                         now: Date, calendar: Calendar) -> OLTrailing? {
        let day = agendaDay ?? now
        if task.isCompleted && !closing {
            guard let done = task.completedAt else { return nil }
            return calendar.isDate(done, inSameDayAs: day)
                ? .text(CompactText.clock(done, calendar: calendar))
                : .text(CompactText.day(done, now: now, calendar: calendar), tone: .done)
        }
        let repeats = context == .select ? nil : task.recurrence.map(RecurrenceWording.summary)
        if context == .today, !calendar.isDate(day, inSameDayAs: now) {
            if let due = task.dueDate, calendar.isDate(due, inSameDayAs: day) {
                let text = task.includesTime ? "Due at \(CompactText.clock(due, calendar: calendar))"
                    : "Due \(CompactText.day(due, now: now, calendar: calendar))"
                let deadline = CompactText.Due(text: text, tone: .upcoming,
                                               dayOffset: CompactText.dayOffset(from: now, to: due, calendar: calendar))
                return .due(deadline, repeats: repeats)
            }
            if let slot, calendar.isDate(slot, inSameDayAs: day) {
                return .text("Scheduled at \(CompactText.clock(slot, calendar: calendar))")
            }
        }
        if let due = CompactText.due(task.dueDate, includesTime: task.includesTime, now: now, calendar: calendar) {
            // Today says "Today" itself; a timed slot says more than the day.
            if context == .today, due.tone == .today {
                if let slot, CompactText.dayOffset(from: now, to: slot, calendar: calendar) == 0 {
                    return .text(CompactText.clock(slot, calendar: calendar), tone: .due)
                }
                if !task.includesTime && !showsDueToday { return repeats.map { .repeats($0) } }
            }
            return .due(due, repeats: repeats)
        }
        switch context {
        case .today:
            if let slot, CompactText.dayOffset(from: now, to: slot, calendar: calendar) == 0 {
                return .text(CompactText.clock(slot, calendar: calendar), tone: .due)
            }
            if let subtasks, subtasks.total > 0 { return .text("\(subtasks.done) of \(subtasks.total)") }
            return repeats.map { .repeats($0) }
        case .list:
            if task.isStarred { return .star }
            return repeats.map { .repeats($0) }
        case .select:
            return nil
        }
    }
}

/// A repeat as VoiceOver reads its glyph: "Repeats every Wednesday".
enum RecurrenceWording {
    static func summary(_ rule: Recurrence) -> String {
        let text = rule.displayText
        return "Repeats " + text.prefix(1).lowercased() + text.dropFirst()
    }
}

/// A task's long-press menu: the quick changes a row offers without opening it.
struct PhoneTaskMenu: View {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let actions = env.actions
        let store = env.store
        let now = env.now
        if !task.isCompleted {
            Button(task.isStarred ? "Unstar" : "Star", systemImage: task.isStarred ? "star.slash" : "star") {
                actions.edit([task], task.isStarred ? "Unstarred “\(task.displayTitle)”" : "Starred “\(task.displayTitle)”",
                             icon: "star") { store.toggleStar($0) }
            }
            let planned = task.isPlanned(on: now, calendar: env.settings.calendar)
            Button(planned ? "Remove from today" : "Plan for today", systemImage: "sun.max") {
                actions.edit([task], planned ? "Removed from today" : "Planned for today", icon: "sun.max") {
                    if planned { store.deselectForToday($0) } else { store.selectForToday($0, now: now) }
                }
            }
            let calendar = env.settings.calendar
            let tonight = task.dueDate.map {
                calendar.isDate($0, inSameDayAs: now) && Tonight.contains($0, includesTime: task.includesTime, calendar: calendar)
            } ?? false
            if !tonight, Tonight.time(now: now, calendar: calendar) != nil {
                Button("Tonight", systemImage: "moon") { actions.scheduleTonight([task]) }
            }
            Button("Start working", systemImage: "play") {
                if env.actions.startWork(task) { env.navigator.open(.working) }
            }
        }
        Button("Move to Trash", systemImage: "trash", role: .destructive) {
            actions.trash([task])
        }
    }
}
