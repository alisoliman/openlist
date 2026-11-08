import SwiftData
import SwiftUI

/// One scheduling surface; switching sections never dismisses the popover or
/// commits an untouched control. Edits go through the workbench, as the
/// inspector's pills do. Like the design's cards, it fits what it shows, up
/// to a height past which the section scrolls.
struct TaskSchedulePicker: View {
    let block: Block
    @State private var section: DetailPicker
    /// The section's height as last laid out; nil until it first is.
    @State private var contentHeight: CGFloat?
    /// What's staged and not yet set, which Done and a click away set first:
    /// a due phrase or time typed, or the reminder's day and time picked.
    @State private var typedValue: NXPendingCustomValue?
    private static let maximumHeight: CGFloat = 510
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.dismiss) private var dismiss

    init(block: Block, initialSection: DetailPicker = .due) {
        self.block = block
        _section = State(initialValue: initialSection == .labels ? .due : initialSection)
    }

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schedule")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(block.displayTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(NX.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Done", action: done)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary, size: .small))
            }

            // The inspector rows' words, in their order.
            NXSegmented(options: [(DetailPicker.due, "Due"), (.repeatRule, "Repeat"), (.reminder, "Reminder")],
                        selection: section) { section = $0 }
                .accessibilityRepresentation {
                    Picker("Schedule section", selection: $section) {
                        Text("Due").tag(DetailPicker.due)
                        Text("Repeat").tag(DetailPicker.repeatRule)
                        Text("Reminder").tag(DetailPicker.reminder)
                    }
                    .pickerStyle(.segmented)
                }

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
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    // The first height lands as it is; a new section, or one
                    // that grows or shrinks, eases to its own.
                    if contentHeight == nil { contentHeight = height }
                    else { withAnimation(style.ease(200)) { contentHeight = height } }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight ?? Self.maximumHeight, Self.maximumHeight))
        }
        .padding(16)
        .frame(width: 350)
        .presentationBackground(NX.card)
        .tint(style.controlTint)
        .environment(\.calendar, env.settings.calendar)
        .onPreferenceChange(NXPendingCustomValueKey.self) { typedValue = $0 }
        // A click away keeps what was staged, as Done does, with no Cancel
        // to have asked for it to go.
        .onDisappear { _ = typedValue?.commit() }
    }

    /// Closing while something is staged keeps it, as leaving its field
    /// does, where closing the popover may not get to it. Done beeps, and
    /// stays, on what can't be set: text that isn't a date or a time, or a
    /// reminder time that has passed.
    private func done() {
        if let typedValue {
            guard typedValue.commit() else { NSSound.beep(); return }
            self.typedValue = nil
        }
        dismiss()
    }
}
