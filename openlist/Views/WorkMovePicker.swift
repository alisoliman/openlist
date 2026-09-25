import SwiftUI

/// The Work panel's Move planned time…: the block's slot at another time,
/// saved as Plan saves one, with the tray and Undo.
struct WorkMovePicker: View {
    let block: PlannedBlock
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var overlaps: [WorkMoveOverlap] = []
    /// That the calendar changed under the sheet, which asks for another look.
    @State private var feedback: String?
    /// Why the move wasn't saved, drawn as a failure.
    @State private var saveError: String?
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
            Text("The block moves on your calendar, as long as it is. The due date stays the same.")
                .font(.system(size: 12)).foregroundStyle(NX.ink(0.5))
                .fixedSize(horizontal: false, vertical: true)
            if !overlaps.isEmpty {
                Text("It would overlap:").font(.system(size: 12, weight: .medium)).foregroundStyle(NX.ink(0.72))
                ScrollView { WorkMoveOverlapsView(overlaps: overlaps) }
                    .frame(maxHeight: 200)
            }
            if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(NX.ink(0.72)) }
            if let saveError { NXSheetError(saveError) }
            HStack(spacing: 8) {
                Spacer()
                // Esc while a custom start time is typed puts the pill back,
                // as the field's own Escape does, and leaves the sheet open.
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(typedTime == nil ? .cancelAction : nil)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button(overlaps.isEmpty ? "Move" : "Move anyway", action: confirm)
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
    private func refresh() { overlaps = env.calendar.moveOverlaps(block, to: date); feedback = nil; saveError = nil }
    private func confirm() {
        // Return in the time field, or a click here while typing, moves the
        // work to the time typed, not the one before it.
        if let typedTime {
            guard typedTime.commit() else { NSSound.beep(); return }
            self.typedTime = nil
        }
        let current = env.calendar.moveOverlaps(block, to: date)
        guard current == overlaps else {
            overlaps = current
            saveError = nil
            feedback = "The calendar changed. Review what this time overlaps before moving."
            return
        }
        env.workbench.movePlacement(block, to: date)
        if env.store.persistenceError == nil { dismiss() }
        else { feedback = nil; saveError = env.store.persistenceError }
    }
}
