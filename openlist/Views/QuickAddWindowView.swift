import SwiftUI

/// Global capture uses exactly the same draft and confirmation as New Task.
struct QuickAddWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        TaskCaptureView(request: env.quickAddRequest, closeWindow: {
            dismissWindow(id: WindowID.quickAdd)
        })
        .fixedSize(horizontal: false, vertical: true)
        // A widget's list applies to the capture it opened, not to the next
        // time Quick Add opens from the menu or the shortcut.
        .onDisappear { env.quickAddRequest = TaskCaptureRequest() }
    }
}
