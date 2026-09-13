import Foundation

/// Duplicate keeps the existing metadata contract. Template reuse starts a
/// new procedure, with repeating rules only when explicitly requested.
enum CopyMode: Equatable {
    case duplicate
    case template(keepingRecurrence: Bool)

    func apply(to block: Block) {
        guard case let .template(keepingRecurrence) = self else { return }
        block.isCompleted = false
        block.completedAt = nil
        block.dueDate = nil
        block.includesTime = false
        block.reminderAt = nil
        block.selectedForDay = nil
        block.deferredUntil = nil
        block.calendarOccurrenceID = nil
        if keepingRecurrence, var recurrence = block.recurrence {
            recurrence.completedOccurrences = 0
            // A dated end belongs to the old procedure; count limits and the
            // recurrence pattern remain reusable without a stale expiry date.
            recurrence.endDate = nil
            block.recurrence = recurrence
        } else {
            block.recurrenceData = nil
        }
    }
}
