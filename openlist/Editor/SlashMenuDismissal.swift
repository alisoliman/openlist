import AppKit
import SwiftUI

/// Observe outside clicks without swallowing them: a click can dismiss the
/// picker and place the insertion point or activate another control at once.
struct SlashMenuDismissal: NSViewRepresentable {
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onDismiss = onDismiss
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak view, weak coordinator = context.coordinator] event in
            MainActor.assumeIsolated {
                guard let view, let window = view.window else { return }
                if event.window !== window || !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                    coordinator?.onDismiss()
                }
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onDismiss = onDismiss }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator {
        var monitor: Any?
        var onDismiss: () -> Void = {}
    }
}
