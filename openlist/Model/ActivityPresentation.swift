import Foundation

extension ActivityEvent {
    var recordedDetail: String { Self.recordedDetail(kind, detail: detail, change: change) }

    /// An event's `recordedDetail`, from its change decoded already, its due
    /// dates written by `dateText` (a date, and whether it has a time): the
    /// app's words, "Fri 25 09:00", "3 Oct 2025" (`MomentText.moment`), unless
    /// the screen showing it passes its own.
    static func recordedDetail(_ kind: ActivityKind, detail: String, change: TaskActivityChange?,
                               dateText: (Date, Bool) -> String = { MomentText.moment($0, includesTime: $1) }) -> String {
        // A change with neither state only says which change saved it.
        guard let change, change.before != nil || change.after != nil else { return detail }
        let before = change.before
        let after = change.after
        func dueText(_ state: TaskActivityState?) -> String {
            guard let state else { return "Not recorded" }
            guard let date = state.dueDate else { return "No due date" }
            return dateText(date, state.includesTime)
        }
        switch kind {
        case .renamed:
            return "“\(before?.title ?? "Not recorded")” → “\(after?.title ?? "Not recorded")”"
        case .scheduled, .unscheduled:
            return "\(dueText(before)) → \(dueText(after))"
        case .moved:
            return "\(Self.listText(before)) → \(Self.listText(after))"
        case .completed:
            guard change.completionID != nil else { return "Open → Completed" }
            let completed = change.completedDueDate.map {
                dateText($0, (after?.includesTime ?? before?.includesTime) == true)
            } ?? "No due date"
            if change.advancesOccurrence {
                return "Completed occurrence: \(completed). Next occurrence: \(dueText(after))."
            }
            return "Completed occurrence: \(completed)."
        case .completionUndone:
            return "Completion undone. Restored occurrence: \(dueText(after))."
        case .reopened:
            return "Completed → Open"
        case .restored:
            return "Restored task in \(Self.listText(after)), \(dueText(after))."
        case .created:
            return "\(Self.listText(after)) · \(dueText(after))"
        case .deleted:
            return "Task deleted; its recorded history is retained."
        default:
            return detail
        }
    }

    private static func listText(_ state: TaskActivityState?) -> String {
        guard let state else { return "Not recorded" }
        return state.listTitle.isEmpty ? (state.listID == nil ? "No list" : "Unavailable list") : state.listTitle
    }
}
