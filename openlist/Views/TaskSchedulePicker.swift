import SwiftUI

/// One scheduling surface; switching sections never dismisses the popover or
/// commits an untouched control. Edits use the existing store semantics.
struct TaskSchedulePicker: View {
    let block: Block
    @State private var section: DetailPicker
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    init(block: Block, initialSection: DetailPicker = .due) {
        self.block = block
        _section = State(initialValue: initialSection == .labels ? .due : initialSection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Schedule").font(.headline)
                    Text(block.displayTitle)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .controlSize(.small)
            }

            Picker("Schedule section", selection: $section) {
                Text("Date & time").tag(DetailPicker.due)
                Text("Reminder").tag(DetailPicker.reminder)
                Text("Repeat").tag(DetailPicker.repeatRule)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                Group {
                    switch section {
                    case .due, .labels: DueDatePicker(block: block)
                    case .reminder: ReminderPicker(block: block)
                    case .repeatRule: RecurrencePicker(block: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: 510)
        }
        .padding(16)
        .frame(width: 350)
        .background(Theme.chrome)
        .environment(\.calendar, env.settings.calendar)
    }
}
