import AppKit
import SwiftData
import SwiftUI
import UserNotifications

/// Reminder time editor, offering offsets relative to the due date.
struct ReminderPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    @State private var customDate: Date = .now

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
                        env.store.setReminder(nil, for: block)
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
                HStack(spacing: 8) {
                    DatePicker("Remind me at", selection: $customDate)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Spacer(minLength: 6)
                    Button("Set reminder") {
                        env.store.setReminder(customDate, for: block)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .primary, size: .small))
                }
            }

            TaskReminderStatus(block: block)
        }
        .onChange(of: block.reminderAt) { _, date in
            customDate = date ?? block.dueDate ?? .now
        }
        .onAppear {
            customDate = block.reminderAt ?? block.dueDate ?? .now

        }
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
            env.store.setReminder(date, for: block)
        } label: {
            Text(title)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
