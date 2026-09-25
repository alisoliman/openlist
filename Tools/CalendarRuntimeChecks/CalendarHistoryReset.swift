import SwiftData

/// A calendar-only reset for the checks: every work session, completion
/// record and placement goes and the tasks stay, as history vanishing under
/// running work would leave them. The app has none of its own; Settings'
/// Delete everything (`permanentlyResetLibrary`) takes the library too.
extension Store {
    func clearCalendarHistory() {
        do {
            for session in try context.fetch(FetchDescriptor<WorkSession>()) { context.delete(session) }
            for record in try context.fetch(FetchDescriptor<CompletionRecord>()) { context.delete(record) }
            for placement in try context.fetch(FetchDescriptor<SchedulePlacement>()) { context.delete(placement) }
            calendarPlannedBlocks = []
            completionUndo = nil
            completionUndoChanges.removeAll()
            pendingCompletionUndoChanges.removeAll()
            for registration in completionUndoRegistrations.values {
                registration.manager?.removeAllActions(withTarget: registration)
            }
            completionUndoRegistrations.removeAll()
            save()
        } catch {
            persistenceError = "Calendar history could not be cleared. \(error.localizedDescription)"
        }
    }
}
