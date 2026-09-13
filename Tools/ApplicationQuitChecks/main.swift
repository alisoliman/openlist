import AppKit
import Foundation

func trace(_ value: String) {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
}

@MainActor final class QuitDelegate: NSObject, NSApplicationDelegate {
    let rejectsFirst: Bool
    var attempts = 0
    init(rejectsFirst: Bool) { self.rejectsFirst = rejectsFirst }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // A restore cancelled after scheduling must not quit the app.
            ApplicationQuit.request(when: { false })
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated {
                    precondition(self.attempts == 0, "Cancelled quit reached the delegate")
                    trace("cancelled request preserved app")
                    Task { @MainActor in ApplicationQuit.request() }
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        attempts += 1
        let shouldQuit = !rejectsFirst || attempts > 1
        trace("delegate attempt \(attempts)")
        Task { @MainActor in
            // Same executor boundary as the real delegate's draft/final save.
            await Task.yield()
            trace("delegate reply \(shouldQuit)")
            sender.reply(toApplicationShouldTerminate: shouldQuit)
            if !shouldQuit {
                // Model the next user retry after AppKit has returned from the
                // rejected request, rather than reentering the same quit loop.
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                    MainActor.assumeIsolated { ApplicationQuit.request() }
                }
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        precondition(attempts == (rejectsFirst ? 2 : 1), "Unexpected termination attempts")
        trace("quit completed")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited) // No windows, Dock activation or user UI.
let delegate = QuitDelegate(rejectsFirst: CommandLine.arguments[1] == "retry")
app.delegate = delegate
app.run()
