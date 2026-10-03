import SwiftUI

struct CalendarSessionRow: View {
    let session: WorkSession
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @State private var isEditing = false
    /// The minutes as typed. A number field on the Mac only takes its text
    /// when editing ends, so Save would read the value from before it.
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                Group {
                    Text(NXFormat.moment(session.startedAt))
                    Text(status)
                }
                .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.5))
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(env.calendar.recordedMinutes(for: session).formatted(.number.precision(.fractionLength(0)))) min")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(NX.ink)
                if session.correctedMinutes != nil {
                    Text("Corrected").font(.system(size: 11, weight: .semibold)).foregroundStyle(style.accent)
                }
                if session.endedAt != nil {
                    Button("Correct time…") {
                        typed = env.calendar.recordedMinutes(for: session).formatted(.number.precision(.fractionLength(0)))
                        isEditing = true
                    }
                        .buttonStyle(NXPanelButtonStyle(kind: .link, size: .small))
                        .padding(.trailing, -5)
                }
            }
        }
        .popover(isPresented: $isEditing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Correct recorded time")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NX.ink)
                NXPanelField {
                    TextField("Minutes", text: $typed)
                        .focused($fieldFocused)
                        .onSubmit(save)
                        .accessibilityLabel("Corrected minutes")
                }
                .frame(width: 140)
                // Once the popover is on screen, or the focus can miss it.
                .onAppear { DispatchQueue.main.async { fieldFocused = true } }
                if session.correctedMinutes != nil {
                    Button("Restore original duration") {
                        env.store.correctSession(session, minutes: nil); env.calendar.storeDidChange(); isEditing = false
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary, size: .small))
                }
                HStack(spacing: 8) {
                    Button("Cancel") { isEditing = false }
                        .buttonStyle(NXPanelButtonStyle(kind: .secondary, size: .small))
                    Spacer()
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(typedMinutes == nil)
                        .help(typedMinutes == nil ? "Type the minutes, 0 or more" : "Save the corrected time (↩)")
                    .buttonStyle(NXPanelButtonStyle(kind: .primary, size: .small))
                }
            }
            .padding(16)
            .frame(width: 290)
            .presentationBackground(NX.card)
        }
    }

    private var typedMinutes: Double? {
        guard let minutes = try? Double(typed.trimmingCharacters(in: .whitespaces), format: .number),
              minutes.isFinite, minutes >= 0 else { return nil }
        return minutes
    }

    private func save() {
        // Return can reach both the field and the default button.
        guard isEditing else { return }
        guard let minutes = typedMinutes else { NSSound.beep(); return }
        env.store.correctSession(session, minutes: minutes)
        env.calendar.storeDidChange()
        isEditing = false
    }

    /// Why the session stopped, in the Work panel's words, or where it is
    /// still open: here, on another Mac, or left unfinished by this one.
    private var status: String {
        guard session.endedAt == nil else { return WorkSession.stopText(session.pauseReason) }
        if env.calendar.activeSession?.id == session.id { return "Recording on this Mac" }
        let elsewhere = env.store.calendarDeviceID.map { $0 != session.deviceID } ?? false
        return elsewhere ? "Recording on another Mac" : "Not finished"
    }
}
