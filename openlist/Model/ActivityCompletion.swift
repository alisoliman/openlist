import Foundation

/// A completion action copied from saved history, independent of live tasks.
nonisolated struct ActivityCompletion: Identifiable, Equatable, Sendable {
    var id: UUID
    var taskID: UUID?
    var completionID: UUID?
    var occurrenceID: UUID?
    var cycleID: UUID?
    var wasRecurring: Bool?
    var date: Date
    var title: String
    var listTitle: String
    var hasConflictingDetails = false

    @MainActor init(event: ActivityEvent, matchingRecord: CompletionRecord?) {
        let change = event.change
        id = event.id
        taskID = event.blockID
        completionID = change?.completionID
        // The record is only a fallback for an existing event, never a second
        // history source. Clearing activity cannot resurrect calendar data.
        let record = matchingRecord.flatMap {
            $0.id == change?.completionID && $0.taskID == event.blockID ? $0 : nil
        }
        occurrenceID = change?.completedOccurrenceID ?? record?.occurrenceID
        cycleID = change?.completionCycleID
        wasRecurring = change?.completionWasRecurring ?? record?.wasRecurring
        // Old advancing events establish recurrence, but an old before state
        // alone does not identify every completion in a multi-action commit.
        if wasRecurring == nil, change?.advancesOccurrence == true { wasRecurring = true }
        date = change?.completedAt ?? record?.completedAt ?? event.timestamp
        title = event.title
        listTitle = event.listTitle
    }

    init(id: UUID = UUID(), taskID: UUID?, completionID: UUID? = nil,
         occurrenceID: UUID? = nil, cycleID: UUID? = nil, wasRecurring: Bool?, date: Date,
         title: String = "Task", listTitle: String = "") {
        self.id = id
        self.taskID = taskID
        self.completionID = completionID
        self.occurrenceID = occurrenceID
        self.cycleID = cycleID
        self.wasRecurring = wasRecurring
        self.date = date
        self.title = title
        self.listTitle = listTitle
    }

    /// Compatible copies enrich the first countable saved action. An older
    /// incomplete event's commit time is not an invented completion timestamp.
    /// Contradictory identities remain explicitly uncounted.
    static func mergingDuplicates(_ copies: [Self]) -> Self {
        let countable = copies.filter {
            !$0.hasConflictingDetails && $0.taskID != nil && $0.wasRecurring != nil
                && ($0.wasRecurring == false || $0.cycleID != nil || $0.occurrenceID != nil)
        }
        var result = (countable.isEmpty ? copies : countable).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.id != $1.id { return $0.id.uuidString < $1.id.uuidString }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.listTitle < $1.listTitle
        }[0]
        let tasks = Set(copies.compactMap(\.taskID))
        let records = Set(copies.compactMap(\.completionID))
        let occurrences = Set(copies.compactMap(\.occurrenceID))
        let cycles = Set(copies.compactMap(\.cycleID))
        let recurring = Set(copies.compactMap(\.wasRecurring))
        result.hasConflictingDetails = copies.contains(where: \.hasConflictingDetails)
            || [tasks.count, records.count, occurrences.count, cycles.count, recurring.count].contains { $0 > 1 }
        result.taskID = tasks.count == 1 ? tasks.first : nil
        result.completionID = records.count == 1 ? records.first : nil
        result.occurrenceID = occurrences.count == 1 ? occurrences.first : nil
        result.cycleID = cycles.count == 1 ? cycles.first : nil
        result.wasRecurring = recurring.count == 1 ? recurring.first : nil
        return result
    }
}
