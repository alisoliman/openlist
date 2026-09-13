import AppKit
import Foundation

@MainActor enum ApplicationQuit {
    private static var isRequesting = false
    /// terminateLater may run an AppKit nested event loop while our delegate
    /// awaits a MainActor task. Enter from a run-loop callback, outside any
    /// Swift task/dispatch job, so that reply task can acquire the executor.
    static func request(when allowed: @escaping @MainActor () -> Bool = { true }) {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                guard allowed(), !isRequesting else { return }
                isRequesting = true
                NSApplication.shared.terminate(nil)
                isRequesting = false
            }
        }
    }
}
