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

    private var calendar: Calendar { env.settings.calendar }

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: block.reminderAt == nil ? "bell.slash" : "bell")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(block.reminderAt == nil ? NX.ink(0.4) : style.accent)
                    .accessibilityHidden(true)
                Text(block.reminderAt.map { Store.absoluteDateText($0, includesTime: true) } ?? "No reminder")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                Spacer(minLength: 6)
                if block.reminderAt != nil {
                    Button("Remove reminder") {
                        env.workbench.setReminder(block.id, at: nil)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .destructive, size: .small))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                NXCapsTitle(text: "Before it’s due")
                if block.dueDate != nil {
                    NXFlow(spacing: 4) {
                        offsetPill("At the due time", minutes: 0)
                        offsetPill("10 minutes before", minutes: -10)
                        offsetPill("1 hour before", minutes: -60)
                        offsetPill("1 day before", minutes: -1_440)
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
                        env.workbench.setReminder(block.id, at: customDate)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .primary, size: .small))
                }
                if picksDay {
                    CalendarMonthPicker(selection: customDate, calendar: calendar) { day in
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
            customDate = date ?? offsetDate(minutes: 0) ?? .now
        }
        .onAppear {
            customDate = block.reminderAt ?? offsetDate(minutes: 0) ?? .now
        }
        .onPreferenceChange(NXPendingCustomValueKey.self) { typedTime = $0 }
        // "Remind me at" is a draft only Set reminder sets, so the Schedule
        // popover's Done closes over a time typed here as over a day picked.
        .transformPreference(NXPendingCustomValueKey.self) { $0 = nil }
    }

    /// The reminder an offset from the due date would set, at 9:00 on a date without a time.
    private func offsetDate(minutes: Int) -> Date? {
        guard let dueDate = block.dueDate else { return nil }
        let base = block.includesTime
            ? dueDate
            : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
        return base.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func offsetPill(_ title: String, minutes: Int) -> some View {
        let date = offsetDate(minutes: minutes)
        let isOn = date.flatMap { date in block.reminderAt.map { abs($0.timeIntervalSince(date)) < 1 } } ?? false
        return NXInspectorPill(isOn: isOn) {
            guard let date = offsetDate(minutes: minutes) else { return }
            env.workbench.setReminder(block.id, at: date)
        } label: {
            Text(title)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
