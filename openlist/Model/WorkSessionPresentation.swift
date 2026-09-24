import Foundation

extension WorkSession {
    /// Why a session stopped recording, as Work history and the Work panel
    /// word it: "Paused while the Mac was asleep", "Ended when the task was
    /// done". Sessions keep the reason they were saved with, so older reasons
    /// read the same way.
    static func stopText(_ reason: String?) -> String {
        switch reason {
        case nil, "Paused": "Paused"
        case "Switched task": "Paused when you switched tasks"
        case "Stopped working": "Paused when you stopped working"
        case "Mac slept": "Paused while the Mac was asleep"
        case "Screen slept": "Paused while the screen was asleep"
        case "Mac locked": "Paused while the Mac was locked"
        case "Mac was unavailable": "Paused while the Mac was away"
        case "Openlist closed", "Openlist restarted", "Recovered before starting": "Paused when Openlist closed"
        case "Deferred": "Paused when the task was deferred"
        case "List unavailable": "Paused while its list was unavailable"
        case "Completed": "Ended when the task was done"
        case "Reopened": "Ended when the task was reopened"
        case "Next occurrence": "Ended when the task repeated"
        case "Moved to Trash": "Ended when the task moved to Trash"
        case "Task deleted": "Ended when the task was deleted"
        // The old editor's name for a text line.
        case "Changed to a note": "Ended when the task was turned into text"
        case let reason? where reason.hasPrefix("Library restored"): "Paused when the library was restored"
        case let reason?: "Paused — \(reason)"
        }
    }
}
