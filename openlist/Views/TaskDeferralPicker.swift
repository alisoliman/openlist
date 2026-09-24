import SwiftData
import SwiftUI

/// Moves a task's remaining work to a later day, from the inspector's plan card.
struct TaskDeferralPicker: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Defer work")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(block.displayTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.5))
                    .lineLimit(2)
            }
            DatePicker(selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date) {
                Text("Resume planning on")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NX.ink)
            }
            Text("Remaining work will use the next available time on or after this day. The due date stays the same.")
                .font(.system(size: 11.5))
                .foregroundStyle(NX.ink(0.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary, size: .small))
                Spacer()
                Button("Defer") { env.calendar.deferTask(task: block, to: date); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary, size: .small))
            }
        }
        .padding(16)
        .frame(width: 320)
        .presentationBackground(NX.card)
        .tint(style.accent)
    }
}
