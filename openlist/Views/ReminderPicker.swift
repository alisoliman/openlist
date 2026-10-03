import AppKit
import SwiftData
import SwiftUI
import UserNotifications

/// Reminder time editor, offering offsets relative to the due date. Each
/// change goes through the workbench: one Undo step, with its tray.
struct ReminderPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    @State private var customDate: Date = .now
    @State private var picksDay = false
    /// A time still being typed as Custom…, which Set reminder sets first.
    @State private var typedTime: NXPendingCustomValue?
    /// Set reminder was asked for a time that has passed, which would never ring.
    @State private var refusedPast = false

    private var calendar: Calendar { env.settings.calendar }

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    /// The due time a timed task with no reminder of its own reminds you at,
    /// as the Store schedules it.
    static func dueTimeReminder(of block: Block) -> Date? {
        block.reminderAt == nil && block.includesTime ? block.dueDate : nil
    }

    private var liveContent: some View {
        let dueTime = Self.dueTimeReminder(of: block)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                // A reminder at the due time rings grey, not being one of its own.
                Image(systemName: block.reminderAt == nil && dueTime == nil ? "bell.slash" : "bell")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(block.reminderAt == nil ? NX.ink(0.4) : style.accent)
                    .accessibilityHidden(true)
                // As the Reminder pill that opens it reads, with the time.
                Text(block.reminderAt.map { NXFormat.dueAndClock($0) } ?? dueTime.map { NXFormat.atDueTime($0) } ?? "No reminder")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                Spacer(minLength: 6)
                // Grey, as the design's None clears a date: it can be undone,
                // and red is for deleting things.
                if block.reminderAt != nil {
                    Button("Remove reminder") {
                        env.workbench.setReminder(block.id, at: nil)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary, size: .small))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                NXCapsTitle(text: "Before it’s due")
                if block.dueDate != nil {
                    NXFlow(spacing: 4) {
                        offsetPill("At the due time", ReminderOffset())
                        offsetPill("10 minutes before", ReminderOffset(minutes: -10))
                        offsetPill("1 hour before", ReminderOffset(minutes: -60))
                        offsetPill("1 day before", ReminderOffset(days: -1))
                    }
                } else {
                    Text("Add a due date to use relative reminders.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NX.ink(0.45))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                NXCapsTitle(text: "Remind me at")
                HStack(spacing: 6) {
                    NXDatePill(label: "Reminder day", date: customDate, isOpen: picksDay) {
                        withAnimation(style.ease(180)) { picksDay.toggle() }
                    }
                    NXTimePill(label: "Reminder time", minute: CalendarMonthGrid.minute(of: customDate, calendar: calendar)) { minute in
                        customDate = CalendarMonthGrid.date(customDate, atMinute: minute, calendar: calendar)
                    }
                    Spacer(minLength: 6)
                    Button("Set reminder") {
                        // A click here while typing sets the time typed, not
                        // the one the pill showed before it.
                        if let typedTime {
                            guard typedTime.commit() else { NSSound.beep(); return }
                            self.typedTime = nil
                        }
                        guard customDate > .now else {
                            NSSound.beep()
                            refusedPast = true
                            return
                        }
                        env.workbench.setReminder(block.id, at: customDate)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .primary, size: .small))
                    .disabled(typedTime == nil && customDate <= .now)
                    .help(customDate <= .now ? "Choose a time that hasn’t passed" : "Remind me at this time")
                }
                if refusedPast || (typedTime == nil && customDate <= .now) {
                    Text("That time has passed. Choose a later one.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NX.redText)
                        .accessibilityAddTraits(.isStaticText)
                }
                if picksDay {
                    CalendarMonthPicker(selection: customDate, calendar: calendar, earliest: .now) { day in
                        customDate = CalendarMonthGrid.date(day, atMinute: CalendarMonthGrid.minute(of: customDate, calendar: calendar),
                                                            calendar: calendar)
                        withAnimation(style.ease(180)) { picksDay = false }
                    }
                    .transition(.opacity)
                }
            }

            TaskReminderStatus(block: block)
        }
        .onChange(of: block.reminderAt) { _, date in
            customDate = Self.upcoming(date ?? offsetDate(ReminderOffset()), calendar: calendar)
        }
        .onChange(of: customDate) { refusedPast = false }
        .onAppear {
            customDate = Self.upcoming(block.reminderAt ?? offsetDate(ReminderOffset()), calendar: calendar)
        }
        .onPreferenceChange(NXPendingCustomValueKey.self) { typedTime = $0 }
        // "Remind me at" is a draft only Set reminder sets, so the Schedule
        // popover's Done closes over a time typed here as over a day picked.
        .transformPreference(NXPendingCustomValueKey.self) { $0 = nil }
    }

    /// `date` while it's still ahead; otherwise, as for an overdue task or
    /// one with no date, the next quarter hour, so Set reminder starts from a
    /// time that can ring.
    static func upcoming(_ date: Date?, now: Date = .now, calendar: Calendar) -> Date {
        if let date, date > now { return date }
        let start = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let quarters = Int(now.timeIntervalSince(start) / 900) + 1
        return start.addingTimeInterval(Double(quarters) * 900)
    }

    /// The reminder an offset from the due date would set, at 9:00 on a date
    /// without a time. A day before is a calendar day, at the same clock time
    /// on a daylight-saving change.
    private func offsetDate(_ offset: ReminderOffset) -> Date? {
        guard let dueDate = block.dueDate else { return nil }
        let base = block.includesTime
            ? dueDate
            : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
        return offset.date(from: base, calendar: calendar)
    }

    /// Whether `offset` is when the task reminds you. At the due time is lit
    /// too for a timed task with no reminder of its own.
    private func isCurrent(_ offset: ReminderOffset) -> Bool {
        let date = offsetDate(offset)
        return date.flatMap { date in block.reminderAt.map { abs($0.timeIntervalSince(date)) < 1 } }
            ?? (offset == ReminderOffset() && Self.dueTimeReminder(of: block) != nil)
    }

    private func offsetPill(_ title: String, _ offset: ReminderOffset) -> some View {
        let isOn = isCurrent(offset)
        // An offset that has already passed, as on an overdue task, would never ring.
        let passed = !isOn && (offsetDate(offset).map { $0 <= .now } ?? false)
        return NXInspectorPill(isOn: isOn) {
            // Choosing the current time again saves nothing, as in Repeat;
            // at the due time it would pin a reminder of its own there.
            guard !isCurrent(offset), let date = offsetDate(offset), date > .now else { return }
            env.workbench.setReminder(block.id, at: date)
        } label: {
            Text(title)
        }
        .disabled(passed)
        .opacity(passed ? 0.45 : 1)
        .help(passed ? "This time has passed" : "Remind me \(title.lowercased())")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
