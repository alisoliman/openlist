import SwiftUI

struct WorkSwitchConfirmation: View {
    let reference: WorkTaskReference
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Switch to \(env.calendar.validWorkTask(reference)?.displayTitle ?? "another task")?").font(.title3.weight(.semibold))
            if let session = env.calendar.activeSession {
                Text("Save \(env.calendar.recordedMinutes(for: session).formatted(.number.precision(.fractionLength(0)))) minutes on \(session.title), then start a new session.")
                    .fixedSize(horizontal: false, vertical: true)
            } else { Text("The previous session has stopped. Start this task now?") }
            HStack {
                Button("Cancel") { env.calendar.cancelWorkSwitch() }
                Spacer()
                Button("Switch task") { env.calendar.confirmWorkSwitch() }.buttonStyle(.borderedProminent)
            }
        }
    }
}
