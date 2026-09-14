import SwiftUI

/// Keep the control in the keyboard and accessibility trees even while its
/// glyph is quiet. Focusing the button itself reveals it before activation.
struct TaskDetailButton: View {
    let title: String
    let isRevealed: Bool
    let action: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var isFocused: Bool

    private var showsAction: Bool { isRevealed || isFocused || voiceOverEnabled }

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .opacity(showsAction ? 1 : 0)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .help("Open details (⌘↩)")
        .accessibilityLabel("Open details for \(title)")
    }
}
