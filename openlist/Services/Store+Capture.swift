//
//  Store+Capture.swift
//  openlist
//

import Foundation
import SwiftData

/// What an interactive capture saves: the title, and the date, repeat and
/// labels its tokens named, as the capture card's chips previewed them.
/// Building one never creates model records.
struct CaptureSnapshot {
    var title: String
    var date: Date?
    var includesTime = false
    var recurrence: Recurrence?
    var labels: [String] = []
}

extension Store {
    /// Save a capture atomically. Failure rolls back only this capture;
    /// existing editor changes are flushed before starting the transaction.
    /// The task goes at the end of its list's document, as the design's
    /// capture, which gives it no place of its own, sorts it after every line.
    func saveCapture(_ snapshot: CaptureSnapshot, destinationID: UUID?, selectedForDay: Date? = nil) throws -> Block {
        guard !snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureError.emptyTitle
        }
        try persistChanges()
        guard let destination = list(id: destinationID) ?? inboxList(), !destination.isEffectivelyArchived else {
            throw CaptureError.unavailableDestination
        }
        isSavingSuspended = true
        defer { isSavingSuspended = false }
        do {
            let block = appendBlock(kind: .task, to: DocumentContext(listID: destination.id))
            setPlainText(block, snapshot.title)
            block.dueDate = snapshot.date
            block.selectedForDay = selectedForDay.map { Calendar.current.startOfDay(for: $0) }
            block.includesTime = snapshot.includesTime
            block.recurrence = snapshot.recurrence?.anchored(to: snapshot.date)
            block.labelIDs = snapshot.labels.compactMap { findOrCreateLabel(named: $0)?.id }
            log(.created, title: block.displayTitle, block: block, list: destination)
            try persistChanges()
            scheduleReminderIfNeeded(for: block)
            return block
        } catch {
            context.rollback()
            pendingActivity.removeAll()
            throw error
        }
    }

    enum CaptureError: LocalizedError {
        case emptyTitle, unavailableDestination
        var errorDescription: String? {
            switch self {
            case .emptyTitle: "Enter a task title before adding it."
            case .unavailableDestination: "That list is unavailable. Choose Inbox or another active list."
            }
        }
    }

    // MARK: - Taking back a creation

    /// Undo of a capture: erases the new task as though it was never added,
    /// with no Trash entry, reminder or history left behind, and returns what
    /// `restoreDiscardedTask` needs to bring the same task back. Returns nil
    /// and leaves the task alone once it holds more than its own fields
    /// (subtasks, files, a calendar plan, work or a completion), which only
    /// Trash may take.
    func discardCapturedTask(id: UUID) -> BackupBlock? {
        guard let block = block(id: id), block.isTask, block.mediaFilename == nil, attachments(for: id).isEmpty,
              (try? context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.parentID == id }))) == 0,
              (try? context.fetchCount(FetchDescriptor<SchedulePlacement>(predicate: #Predicate { $0.taskID == id }))) == 0,
              (try? context.fetchCount(FetchDescriptor<WorkSession>(predicate: #Predicate { $0.taskID == id }))) == 0,
              (try? context.fetchCount(FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.taskID == id }))) == 0
        else { return nil }
        let snapshot = BackupBlock(block)
        do {
            try persistChanges()
            // Its creation event goes too, and the deletion logs nothing.
            try withoutLogging {
                for event in try context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == id })) {
                    context.delete(event)
                }
                context.delete(block)
                try persistChanges()
            }
        } catch {
            context.rollback()
            pendingActivity.removeAll()
            return nil
        }
        permanentlyErasedBlockIDs.insert(id)
        onEditorBlocksRemoved?([id])
        return snapshot
    }

    /// Redo of a discarded capture: the same task, identity and fields, back
    /// where it was, logged as created again. A list that has gone since
    /// leaves it in Inbox.
    @discardableResult
    func restoreDiscardedTask(_ snapshot: BackupBlock) -> Block? {
        let id = snapshot.id
        guard (try? context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.id == id }))) == 0,
              let destination = list(id: snapshot.listID) ?? inboxList() else { return nil }
        let block = snapshot.model()
        block.listID = destination.id
        if block.parentID.flatMap({ self.block(id: $0) })?.listID != destination.id { block.parentID = nil }
        block.labelIDs = resolvedLabelIDs(snapshot.labelIDs)
        context.insert(block)
        do {
            try persistChanges()
        } catch {
            context.rollback()
            if block.modelContext != nil { context.delete(block) }
            pendingActivity.removeAll()
            return nil
        }
        permanentlyErasedBlockIDs.remove(id)
        return block
    }

    /// Undo of New list: erases the list with no Trash entry while it is still
    /// empty, and returns what `restoreDiscardedList` needs to bring it back.
    /// Returns nil and leaves the list alone once it has content, child lists
    /// or a cover, which only Trash may take.
    func discardCreatedList(id: UUID) -> BackupTaskList? {
        guard let list = list(id: id), list.id == id, !list.isSystemInbox, list.coverFilename == nil,
              (try? context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.listID == id }))) == 0,
              (try? context.fetchCount(FetchDescriptor<TaskList>(predicate: #Predicate {
                  $0.parentListID == id || $0.mergedIntoID == id
              }))) == 0
        else { return nil }
        let snapshot = BackupTaskList(list)
        do {
            try persistChanges()
            let events = try context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate {
                $0.listID == id && $0.blockID == nil
            }))
            for event in events { context.delete(event) }
            context.delete(list)
            try persistChanges()
        } catch {
            context.rollback()
            pendingActivity.removeAll()
            return nil
        }
        return snapshot
    }

    /// Redo of a discarded New list: the same list back in its section, or
    /// the default one if that section has gone since.
    @discardableResult
    func restoreDiscardedList(_ snapshot: BackupTaskList) -> TaskList? {
        let id = snapshot.id
        guard (try? context.fetchCount(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id }))) == 0 else { return nil }
        let list = snapshot.model()
        if let sectionID = list.sectionID, !allSections().contains(where: { $0.id == resolvedSectionID(sectionID) }) {
            list.sectionID = defaultSection()?.id
        }
        if list.parentListID.flatMap({ self.list(id: $0) }) == nil { list.parentListID = nil }
        context.insert(list)
        log(.listCreated, title: list.displayTitle, list: list)
        do {
            try persistChanges()
        } catch {
            context.rollback()
            if list.modelContext != nil { context.delete(list) }
            pendingActivity.removeAll()
            return nil
        }
        return list
    }

    // MARK: - Command dispatch

    /// Runs a command that only needs a set of blocks.
    ///
    /// Both the outline and the cross-list screens issue the same task
    /// commands; keeping the bodies here means there is one definition of what
    /// ⌘D or ⌃T does, rather than one per screen.
    ///
    /// - Returns: `false` for commands that need an outline and so cannot be
    ///   served from a set of blocks alone.
    @discardableResult
    func perform(_ command: EditorCommand, on targets: [Block], undoManager: UndoManager? = nil) -> Bool {
        switch command {
        case .toggleCompletion:
            batch { for block in targets where block.isTask { toggleCompletion(block) } }

        case .setDueToday:
            batch { for block in targets where block.isTask { setDueToday(block) } }

        case .clearDueDate:
            batch { for block in targets where block.isTask { setDueDate(nil, for: block) } }

        case .clearLabels:
            batch { for block in targets where block.isTask { clearLabels(on: block) } }

        case .toggleStar:
            batch { for block in targets where block.isTask { toggleStar(block) } }

        case .deleteSelection:
            return trashBlocks(targets, undoManager: undoManager)

        case .newTask, .openDetails, .pickDueDate, .pickLabel,
             .indent, .outdent, .moveUp, .moveDown, .expandAll, .collapseAll:
            // Needs an editor, a picker, or a destination the store cannot pick.
            return false
        }
        return true
    }

    /// Runs `body` with saving suspended, then saves once.
    ///
    /// Bulk edits otherwise open one transaction — and fire one widget
    /// refresh — per block touched.
    func batch(_ body: () -> Void) {
        let wasSuspended = isSavingSuspended
        isSavingSuspended = true
        body()
        isSavingSuspended = wasSuspended
        save()
    }
}
