import SwiftUI

struct CalendarSessionRow: View {
    let session: WorkSession
    @Environment(AppEnvironment.self) private var env
    @State private var isEditing = false
    @State private var minutes = 0.0
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.body.weight(.medium))
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                Text(session.endedAt == nil ? (env.calendar.activeSession?.id == session.id ? "Active on this Mac" : "Last recorded on another session") : (session.pauseReason ?? "Paused"))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(env.calendar.recordedMinutes(for: session).formatted(.number.precision(.fractionLength(0)))) min").monospacedDigit()
                if session.correctedMinutes != nil { Text("Corrected").font(.caption).foregroundStyle(Theme.accent) }
                if session.endedAt != nil {
                    Button("Correct time…") { minutes = env.calendar.recordedMinutes(for: session); isEditing = true }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .popover(isPresented: $isEditing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Correct recorded time").font(.headline)
                TextField("Minutes", value: $minutes, format: .number).frame(width: 140)
                    .accessibilityLabel("Corrected minutes")
                if session.correctedMinutes != nil {
                    Button("Restore original duration") {
                        env.store.correctSession(session, minutes: nil); env.calendar.storeDidChange(); isEditing = false
                    }
                }
                HStack {
                    Button("Cancel") { isEditing = false }
                    Spacer()
                    Button("Save") {
                        env.store.correctSession(session, minutes: max(0, minutes)); env.calendar.storeDidChange(); isEditing = false
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(16).frame(width: 290)
        }
    }
}
