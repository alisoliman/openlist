import SwiftUI

/// Global capture uses exactly the same draft and confirmation as New Task.
struct QuickAddWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        TaskCaptureView(request: TaskCaptureRequest(), closeWindow: {
            dismissWindow(id: WindowID.quickAdd)
        })
        .fixedSize(horizontal: false, vertical: true)
    }
}
