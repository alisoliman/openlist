import SwiftUI

struct WorkMovePicker: View {
    let block: PlannedBlock
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var changes: [WorkPlanChange] = []
    @State private var feedback: String?
    /// A start time still being typed as Custom…, which Move sets first.
    @State private var typedTime: NXPendingCustomValue?

    private var calendar: Calendar { env.settings.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                NXPanelTitle("Move planned work")
                Text(env.store.block(id: block.taskID)?.displayTitle ?? "Task")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.55))
                    .lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 8) {
                NXCapsTitle(text: "Start")
                // Never before now, as the work can't start in the past.
                CalendarMonthPicker(selection: date, calendar: calendar, earliest: .now) { day in
                    date = CalendarMonthGrid.date(day, atMinute: CalendarMonthGrid.minute(of: date, calendar: calendar),
                                                  notBefore: .now, calendar: calendar)
                }
                HStack(spacing: 8) {
                    Text("At")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(NX.ink(0.6))
                    NXTimePill(label: "Start time", minute: CalendarMonthGrid.minute(of: date, calendar: calendar)) { minute in
                        date = CalendarMonthGrid.date(date, atMinute: minute, notBefore: .now, calendar: calendar)
                    }
                }
            }
            Text("This changes your preferred work time, not your deadline.")
                .font(.system(size: 12)).foregroundStyle(NX.ink(0.5))
            if !changes.isEmpty {
                Text("Other planned work would move:").font(.system(size: 12, weight: .medium)).foregroundStyle(NX.ink(0.72))
                ScrollView { WorkPlanChangesView(changes: changes) }
                    .frame(maxHeight: 200)
            }
            if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(NX.ink(0.72)) }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button(changes.isEmpty ? "Move" : "Move and update plan", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
            }
        }
        .padding(24).frame(width: 400)
        .presentationBackground(NX.card)
        .tint(style.accent)
        .onAppear { date = max(.now, block.start); refresh() }
        .onChange(of: date) { _, _ in refresh() }
        .onPreferenceChange(NXPendingCustomValueKey.self) { typedTime = $0 }
    }
    private func refresh() { changes = env.calendar.previewMove(block, to: date); feedback = nil }
    private func confirm() {
        // Return in the time field, or a click here while typing, moves the
        // work to the time typed, not the one before it.
        if let typedTime {
            guard typedTime.commit() else { NSSound.beep(); return }
            self.typedTime = nil
        }
        let current = env.calendar.previewMove(block, to: date)
        guard current == changes else { changes = current; feedback = "The plan changed. Review these times before moving."; return }
        env.calendar.move(block: block, to: date)
        if env.store.persistenceError == nil { dismiss() }
        else { feedback = env.store.persistenceError }
    }
}
