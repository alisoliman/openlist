import AppKit
import SwiftData
import SwiftUI
import UserNotifications

/// Reminder time editor, offering offsets relative to the due date.
struct ReminderPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env

    @State private var customDate: Date = .now

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(block.reminderAt.map { Store.absoluteDateText($0, includesTime: true) } ?? "No reminder", systemImage: "bell")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 4)
            if block.dueDate != nil {
                VStack(spacing: 2) {
                    offsetRow("At the due time", minutes: 0)
                    offsetRow("10 minutes before", minutes: -10)
                    offsetRow("1 hour before", minutes: -60)
                    offsetRow("1 day before", minutes: -1_440)
                }
                Divider()
            } else {
                Text("Add a due date to use relative reminders.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            DatePicker("Remind me at", selection: $customDate)
                .font(Theme.Font.body)
                .datePickerStyle(.compact)

            Button("Set reminder") {
                env.store.setReminder(customDate, for: block)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if block.reminderAt != nil {
                Button("Remove reminder") {
                    env.store.setReminder(nil, for: block)
                }
                .buttonStyle(.plain)
                .font(Theme.Font.metadata)
                .foregroundStyle(ListAccent.red.color)
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

    private func offsetRow(_ title: String, minutes: Int) -> some View {
        Button {
            guard let dueDate = block.dueDate else { return }
            let base = block.includesTime
                ? dueDate
                : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
            env.store.setReminder(base.addingTimeInterval(TimeInterval(minutes * 60)), for: block)
        } label: {
            HStack {
                Text(title)
                    .font(Theme.Font.body)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
