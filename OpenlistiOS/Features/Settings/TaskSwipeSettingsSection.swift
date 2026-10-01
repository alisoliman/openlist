import SwiftUI

struct TaskSwipeSettingsSection: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        OLGroup("Swipe actions") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    ForEach(TaskSwipePreferences.Slot.allCases, id: \.self) { slot in
                        shortcut(slot)
                    }
                }
                .olCard()
                Text("Swipe right a little for these shortcuts, or swipe farther to add to Today. Swipe left to move a task to Trash.")
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func shortcut(_ slot: TaskSwipePreferences.Slot) -> some View {
        let action = env.taskSwipes.action(for: slot)
        return Menu {
            Picker(slot.title, selection: Binding(get: { env.taskSwipes.action(for: slot) },
                                                  set: { env.taskSwipes.set($0, for: slot) })) {
                ForEach(TaskSwipeAction.allCases) { choice in
                    Label(choice.title, systemImage: choice.symbol).tag(choice)
                }
            }
        } label: {
            OLSettingsRow(slot.title, tile: .accent(action.symbol), separator: slot == .first ? .none : .settings) {
                OLRowValue(action.title)
            }
            .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .accessibilityIdentifier("settings.swipe.\(slot.rawValue)")
    }
}
