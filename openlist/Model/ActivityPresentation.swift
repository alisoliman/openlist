import Foundation

extension ActivityEvent {
    var recordedDetail: String { Self.recordedDetail(kind, detail: detail, change: change) }

    /// An event's `recordedDetail`, from its change decoded already.
    static func recordedDetail(_ kind: ActivityKind, detail: String, change: TaskActivityChange?) -> String {
        // A change with neither state only says which change saved it.
        guard let change, change.before != nil || change.after != nil else { return detail }
        let before = change.before
        let after = change.after
        switch kind {
        case .renamed:
            return "“\(before?.title ?? "Not recorded")” → “\(after?.title ?? "Not recorded")”"
        case .scheduled, .unscheduled:
            return "\(Self.dateText(before)) → \(Self.dateText(after))"
        case .moved:
            return "\(Self.listText(before)) → \(Self.listText(after))"
        case .completed:
            guard change.completionID != nil else { return "Open → Completed" }
            let completed = change.completedDueDate.map {
                MomentText.moment($0, includesTime: (after?.includesTime ?? before?.includesTime) == true)
            } ?? "No due date"
            if change.advancesOccurrence {
                return "Completed occurrence: \(completed). Next occurrence: \(Self.dateText(after))."
            }
            return "Completed occurrence: \(completed)."
        case .completionUndone:
            return "Completion undone. Restored occurrence: \(Self.dateText(after))."
        case .reopened:
            return "Completed → Open"
        case .restored:
            return "Restored task in \(Self.listText(after)), \(Self.dateText(after))."
        case .created:
            return "\(Self.listText(after)) · \(Self.dateText(after))"
        case .deleted:
            return "Task deleted; its recorded history is retained."
        default:
            return detail
        }
    }

    /// A due date as the app's pills write one, with the year when it isn't this one.
    private static func dateText(_ state: TaskActivityState?) -> String {
        guard let state else { return "Not recorded" }
        guard let date = state.dueDate else { return "No due date" }
        return MomentText.moment(date, includesTime: state.includesTime)
    }

    private static func listText(_ state: TaskActivityState?) -> String {
        guard let state else { return "Not recorded" }
        return state.listTitle.isEmpty ? (state.listID == nil ? "No list" : "Unavailable list") : state.listTitle
    }
}
