import SwiftUI

/// Global capture uses exactly the same draft and confirmation as New Task.
struct QuickAddWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissWindow) private var dismissWindow
    /// A widget's Quick Add can name the list or ask to plan for today.
    @State private var request = TaskCaptureRequest()
    @State private var holdsDraft = false

    var body: some View {
        TaskCaptureView(request: request, holdsDraft: $holdsDraft, closeWindow: {
            dismissWindow(id: WindowID.quickAdd)
        })
        .id(request.id)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: env.pendingQuickAddRequest?.id, initial: true) { _, _ in
            guard let pending = env.pendingQuickAddRequest else { return }
            env.pendingQuickAddRequest = nil
            // What's typed here wins: a widget's Quick Add only brings the
            // window forward, and starts a new draft once this one is empty.
            guard !holdsDraft else { return }
            request = pending
        }
    }
}
