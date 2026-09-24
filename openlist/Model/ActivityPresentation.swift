import Foundation

extension ActivityEvent {
    var recordedDetail: String {
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
                $0.formatted(date: .abbreviated, time: (after?.includesTime ?? before?.includesTime) == true ? .shortened : .omitted)
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

    private static func dateText(_ state: TaskActivityState?) -> String {
        guard let state else { return "Not recorded" }
        guard let date = state.dueDate else { return "No due date" }
        return date.formatted(date: .abbreviated, time: state.includesTime ? .shortened : .omitted)
    }

    private static func listText(_ state: TaskActivityState?) -> String {
        guard let state else { return "Not recorded" }
        return state.listTitle.isEmpty ? (state.listID == nil ? "No list" : "Unavailable list") : state.listTitle
    }
}
