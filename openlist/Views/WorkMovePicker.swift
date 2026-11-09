import SwiftUI

/// The Work panel's and a calendar block's Move planned time…: the block's
/// slot at another time, saved as Plan saves one, with the tray and Undo.
/// With `plans`, Not planned yet's Plan at…: the task given a slot at the
/// time picked, as a drop on the calendar gives it one. It draws no chrome
/// of its own: the Work panel shows it in place, and a sheet frames it.
struct WorkMovePicker: View {
    let block: PlannedBlock
    /// Plans the block's task at the time picked, rather than moving a slot it has.
    var plans = false
    /// Its own title, which the Work panel's header gives it instead.
    var showsTitle = true
    /// Cancel, or the move made: the panel goes back to the work, the sheet away.
    let done: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @State private var date = Date.now
    @State private var overlaps: [WorkMoveOverlap] = []
    /// That the calendar changed under the picker, which asks for another look.
    @State private var feedback: String?
    /// Why the move wasn't saved, drawn as a failure.
    @State private var saveError: String?
    /// A start time still being typed as Custom…, which Move sets first.
    @State private var typedTime: NXPendingCustomValue?

    private var calendar: Calendar { env.settings.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if showsTitle { NXPanelTitle(plans ? "Plan a time" : "Move planned work") }
                Text(env.store.block(id: block.taskID)?.displayTitle ?? "Task")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NX.textTertiary)
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
                        .foregroundStyle(NX.textTertiary)
                    NXTimePill(label: "Start time", minute: CalendarMonthGrid.minute(of: date, calendar: calendar)) { minute in
                        date = CalendarMonthGrid.date(date, atMinute: minute, notBefore: .now, calendar: calendar)
                    }
                }
            }
            if !overlaps.isEmpty {
                Text("It would overlap:").font(.system(size: 12, weight: .medium)).foregroundStyle(NX.textSecondary)
                ScrollView { WorkMoveOverlapsView(overlaps: overlaps) }
                    .frame(maxHeight: 200)
            }
            if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(NX.textSecondary) }
            if let saveError { NXSheetError(saveError) }
            HStack(spacing: 8) {
                Spacer()
                // Esc while a custom start time is typed puts the pill back,
                // as the field's own Escape does, and leaves the picker open.
                Button("Cancel", role: .cancel, action: done)
                    .keyboardShortcut(typedTime == nil ? .cancelAction : nil)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button(confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
            }
        }
        .tint(style.controlTint)
        .onAppear { date = max(.now, block.start); refresh() }
        .onChange(of: date) { _, _ in refresh() }
        .onPreferenceChange(NXPendingCustomValueKey.self) { typedTime = $0 }
    }

    private var confirmTitle: String {
        switch (plans, overlaps.isEmpty) {
        case (true, true): "Plan"
        case (true, false): "Plan anyway"
        case (false, true): "Move"
        case (false, false): "Move anyway"
        }
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
            feedback = "The calendar changed. Review what this time overlaps before \(plans ? "planning" : "moving")."
            return
        }
        if plans { env.workbench.plan(block.taskID, at: date) } else { env.workbench.movePlacement(block, to: date) }
        if env.store.persistenceError == nil { done() }
        else { feedback = nil; saveError = env.store.persistenceError }
    }
}
