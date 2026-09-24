import Foundation

extension WorkSession {
    /// Why a session stopped recording, as Work history and the Work panel
    /// word it: "Paused while the Mac was asleep", "Ended when the task was
    /// done", "Stopped". Sessions keep the reason they were saved with, so
    /// older reasons read the same way.
    static func stopText(_ reason: String?) -> String {
        if let ended = endedText(reason) { return ended }
        return switch reason {
        case nil, "Paused": "Paused"
        case "Switched task": "Paused when you switched tasks"
        case "Mac slept": "Paused while the Mac was asleep"
        case "Screen slept": "Paused while the screen was asleep"
        case "Mac locked": "Paused while the Mac was locked"
        case "Mac was unavailable": "Paused while the Mac was away"
        case "Openlist closed", "Openlist restarted", "Recovered before starting": "Paused when Openlist closed"
        case "Deferred": "Paused when the task was deferred"
        case "List unavailable": "Paused while its list was unavailable"
        case "Completion undone": "Paused when the completion was undone"
        case let reason? where reason.hasPrefix("Library restored"): "Paused when the library was restored"
        case let reason?: "Paused — \(reason)"
        }
    }

    /// As `stopText`, for work the Work panel offers to resume: work that
    /// ended with its task reads plainly as paused beside Resume working.
    static func resumableStopText(_ reason: String?) -> String {
        endedText(reason) == nil ? stopText(reason) : "Paused"
    }

    /// The reasons that end the work, with its task or by Stop, rather than pause it.
    private static func endedText(_ reason: String?) -> String? {
        switch reason {
        // Stop ends the work, as its "Stopped — 12:34 recorded" tray says.
        case "Stopped working": "Stopped"
        // A redone completion ends the work again, as the completion did.
        case "Completed", "Completion restored": "Ended when the task was done"
        case "Reopened": "Ended when the task was reopened"
        case "Next occurrence": "Ended when the task repeated"
        case "Moved to Trash": "Ended when the task moved to Trash"
        case "Task deleted": "Ended when the task was deleted"
        // The old editor's name for a text line.
        case "Changed to a note": "Ended when the task was turned into text"
        default: nil
        }
    }
}
