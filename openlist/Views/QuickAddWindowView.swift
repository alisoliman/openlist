import SwiftUI

/// Global capture uses exactly the same draft and confirmation as New Task.
struct QuickAddWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissWindow) private var dismissWindow
    /// A widget's Quick Add can name the list or ask to plan for today.
    @State private var request = TaskCaptureRequest()

    var body: some View {
        TaskCaptureView(request: request, closeWindow: {
            dismissWindow(id: WindowID.quickAdd)
        })
        .id(request.id)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: env.pendingQuickAddRequest?.id, initial: true) { _, _ in
            guard let pending = env.pendingQuickAddRequest else { return }
            env.pendingQuickAddRequest = nil
            request = pending
        }
    }
}
