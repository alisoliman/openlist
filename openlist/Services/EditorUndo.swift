import AppKit
import SwiftData

// Value records keep undo independent of SwiftData objects invalidated by save.
// Only fields changed by this operation are restored on surviving blocks.
private struct EditorBlockRecord: Equatable {
    var id: UUID
    var kindRaw: String
    var text: String
    var richData: Data?
    var sortIndex: Double
    var listID: UUID?
    var parentID: UUID?
    var isCollapsed: Bool
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool
    var completedAt: Date?
    var dueDate: Date?
    var includesTime: Bool
    var reminderAt: Date?
    var isStarred: Bool
    var priorityRaw: Int
    var recurrenceData: Data?
    var labelIDs: [UUID]
    var note: String
    var inboxMembershipData: Data?
    var schedulingEstimateMinutes: Int
    var selectedForDay: Date?
    var deferredUntil: Date?
    var keepsSessionsTogether: Bool
    var tracksAwayFromMac: Bool
    var occurrenceID: UUID
    var mediaFilename: String?
    var mediaData: Data?
    var mediaWidth: Double
    var mediaHeight: Double
    var mediaCaption: String
    init(_ model: Block) {
        id = model.id
        kindRaw = model.kindRaw
        text = model.text
        richData = model.richData
        sortIndex = model.sortIndex
        listID = model.listID
        parentID = model.parentID
        isCollapsed = model.isCollapsed
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        isCompleted = model.isCompleted
        completedAt = model.completedAt
        dueDate = model.dueDate
        includesTime = model.includesTime
        reminderAt = model.reminderAt
        isStarred = model.isStarred
        priorityRaw = model.priorityRaw
        recurrenceData = model.recurrenceData
        labelIDs = model.labelIDs
        note = model.note
        inboxMembershipData = model.inboxMembershipData
        schedulingEstimateMinutes = model.schedulingEstimateMinutes
        selectedForDay = model.selectedForDay
        deferredUntil = model.deferredUntil
        keepsSessionsTogether = model.keepsSessionsTogether
        tracksAwayFromMac = model.tracksAwayFromMac
        occurrenceID = model.occurrenceID
        mediaFilename = model.mediaFilename
        mediaData = model.mediaData
        mediaWidth = model.mediaWidth
        mediaHeight = model.mediaHeight
        mediaCaption = model.mediaCaption
    }
    /// Takes every field `current` has that `expected` doesn't: a change
    /// something else made since the edit last wrote, which the edit's Undo
    /// must leave alone.
    mutating func adopt(changesIn current: Self, since expected: Self) {
        func take<T: Equatable>(_ field: WritableKeyPath<Self, T>) {
            if current[keyPath: field] != expected[keyPath: field] { self[keyPath: field] = current[keyPath: field] }
        }
        take(\.kindRaw); take(\.text); take(\.richData); take(\.sortIndex); take(\.listID); take(\.parentID)
        take(\.isCollapsed); take(\.createdAt); take(\.updatedAt); take(\.isCompleted); take(\.completedAt)
        take(\.dueDate); take(\.includesTime); take(\.reminderAt); take(\.isStarred); take(\.priorityRaw)
        take(\.recurrenceData); take(\.labelIDs); take(\.note); take(\.inboxMembershipData)
        take(\.schedulingEstimateMinutes); take(\.selectedForDay); take(\.deferredUntil)
        take(\.keepsSessionsTogether); take(\.tracksAwayFromMac); take(\.occurrenceID); take(\.mediaFilename)
        take(\.mediaData); take(\.mediaWidth); take(\.mediaHeight); take(\.mediaCaption)
    }
    func apply(to model: Block, replacing old: Self?) {
        if old == nil || old?.id != id { model.id = id }
        if old == nil || old?.kindRaw != kindRaw { model.kindRaw = kindRaw }
        if old == nil || old?.text != text { model.text = text }
        if old == nil || old?.richData != richData { model.richData = richData }
        if old == nil || old?.sortIndex != sortIndex { model.sortIndex = sortIndex }
        if old == nil || old?.listID != listID { model.listID = listID }
        if old == nil || old?.parentID != parentID { model.parentID = parentID }
        if old == nil || old?.isCollapsed != isCollapsed { model.isCollapsed = isCollapsed }
        if old == nil || old?.createdAt != createdAt { model.createdAt = createdAt }
        if old == nil || old?.updatedAt != updatedAt { model.updatedAt = updatedAt }
        if old == nil || old?.isCompleted != isCompleted { model.isCompleted = isCompleted }
        if old == nil || old?.completedAt != completedAt { model.completedAt = completedAt }
        if old == nil || old?.dueDate != dueDate { model.dueDate = dueDate }
        if old == nil || old?.includesTime != includesTime { model.includesTime = includesTime }
        if old == nil || old?.reminderAt != reminderAt { model.reminderAt = reminderAt }
        if old == nil || old?.isStarred != isStarred { model.isStarred = isStarred }
        if old == nil || old?.priorityRaw != priorityRaw { model.priorityRaw = priorityRaw }
        if old == nil || old?.recurrenceData != recurrenceData { model.recurrenceData = recurrenceData }
        if old == nil || old?.labelIDs != labelIDs { model.labelIDs = labelIDs }
        if old == nil || old?.note != note { model.note = note }
        if old == nil || (old?.inboxMembershipData != inboxMembershipData && model.inboxMembershipData == old?.inboxMembershipData) { model.inboxMembershipData = inboxMembershipData }
        if old == nil || old?.schedulingEstimateMinutes != schedulingEstimateMinutes { model.schedulingEstimateMinutes = schedulingEstimateMinutes }
        if old == nil || old?.selectedForDay != selectedForDay { model.selectedForDay = selectedForDay }
        if old == nil || old?.deferredUntil != deferredUntil { model.deferredUntil = deferredUntil }
        if old == nil || old?.keepsSessionsTogether != keepsSessionsTogether { model.keepsSessionsTogether = keepsSessionsTogether }
        if old == nil || old?.tracksAwayFromMac != tracksAwayFromMac { model.tracksAwayFromMac = tracksAwayFromMac }
        if old == nil || old?.occurrenceID != occurrenceID { model.occurrenceID = occurrenceID }
        if old == nil || old?.mediaFilename != mediaFilename { model.mediaFilename = mediaFilename }
        if old == nil || old?.mediaData != mediaData { model.mediaData = mediaData }
        if old == nil || old?.mediaWidth != mediaWidth { model.mediaWidth = mediaWidth }
        if old == nil || old?.mediaHeight != mediaHeight { model.mediaHeight = mediaHeight }
        if old == nil || old?.mediaCaption != mediaCaption { model.mediaCaption = mediaCaption }
    }
}

private struct EditorAttachmentRecord: Equatable {
    var id: UUID
    var blockID: UUID?
    var filename: String
    var contentData: Data?
    var displayName: String
    var contentType: String
    var byteCount: Int
    var sortIndex: Double
    var createdAt: Date
    init(_ model: Attachment) {
        id = model.id
        blockID = model.blockID
        filename = model.filename
        contentData = model.contentData
        displayName = model.displayName
        contentType = model.contentType
        byteCount = model.byteCount
        sortIndex = model.sortIndex
        createdAt = model.createdAt
    }
    func apply(to model: Attachment, replacing old: Self?) {
        if old == nil || old?.id != id { model.id = id }
        if old == nil || old?.blockID != blockID { model.blockID = blockID }
        if old == nil || old?.filename != filename { model.filename = filename }
        if old == nil || old?.contentData != contentData { model.contentData = contentData }
        if old == nil || old?.displayName != displayName { model.displayName = displayName }
        if old == nil || old?.contentType != contentType { model.contentType = contentType }
        if old == nil || old?.byteCount != byteCount { model.byteCount = byteCount }
        if old == nil || old?.sortIndex != sortIndex { model.sortIndex = sortIndex }
        if old == nil || old?.createdAt != createdAt { model.createdAt = createdAt }
    }
}

private struct EditorSnapshot {
    var listIDs: Set<UUID>
    var blocks: [UUID: EditorBlockRecord]
    var attachments: [UUID: EditorAttachmentRecord]
    var labels: [UUID: EditorLabelRecord]
    var hasLabelSnapshot: Bool

    /// - Parameter blockIDs: records only these blocks and their attachments,
    ///   for an edit known to touch nothing else. `nil` records every block.
    init(store: Store, listIDs: Set<UUID>, blockIDs: Set<UUID>? = nil, includingNewLabels: Bool = false) {
        let resolved = Set(listIDs.map { store.resolvedListID($0) ?? $0 })
        self.listIDs = resolved
        let models: [Block]
        if let blockIDs {
            // A line's edit covers a few blocks: fetch those, not their lists.
            let ids = Array(blockIDs)
            let descriptor = FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) && $0.trashID == nil })
            models = ((try? store.context.fetch(descriptor)) ?? []).filter { $0.listID.map(resolved.contains) == true }
        } else {
            models = resolved.flatMap { store.blocks(inList: $0) }
        }
        blocks = Dictionary(uniqueKeysWithValues: models.map { ($0.id, EditorBlockRecord($0)) })
        // One fetch for every block's attachments, not one per block.
        let owners: [UUID?] = models.map(\.id)
        let files = (try? store.context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { owners.contains($0.blockID) })))
            ?? models.flatMap { store.attachments(for: $0.id) }
        attachments = Dictionary(files.map { ($0.id, EditorAttachmentRecord($0)) }, uniquingKeysWith: { first, _ in first })
        if includingNewLabels, let models = try? store.context.fetch(FetchDescriptor<TaskLabel>()) {
            labels = Dictionary(models.filter { !$0.isDeleted }.map { ($0.id, EditorLabelRecord($0)) }, uniquingKeysWith: { first, _ in first })
            hasLabelSnapshot = true
        } else {
            labels = [:]
            hasLabelSnapshot = false
        }
    }

    func files(excluding erasedBlockIDs: Set<UUID>) -> Set<String> {
        Set(blocks.values.filter { !erasedBlockIDs.contains($0.id) }.compactMap(\.mediaFilename)
            + attachments.values.filter { $0.blockID.map(erasedBlockIDs.contains) != true }.map(\.filename))
    }

    func changedIDs(comparedTo other: Self) -> (blocks: Set<UUID>, attachments: Set<UUID>) {
        (Set(blocks.keys).union(other.blocks.keys).filter { blocks[$0] != other.blocks[$0] },
         Set(attachments.keys).union(other.attachments.keys).filter { attachments[$0] != other.attachments[$0] })
    }
}

/// An edit that spans several events, undone as one step: typing in one
/// line, and whatever else changed while that line held the caret.
///
/// Its baseline holds every block the edit has touched, as it was before the
/// edit first touched it, so the one Undo it registers restores exactly
/// those and leaves anything else that changed meanwhile alone.
final class EditorEditSession {
    fileprivate let listIDs: Set<UUID>
    fileprivate var baseline: EditorSnapshot
    fileprivate var media: [String: Data] = [:]
    /// The blocks the edit may have changed, including ones it created.
    fileprivate(set) var touchedIDs: Set<UUID>
    /// The touched blocks and their attachments as the edit itself last left
    /// them. Whatever differs from these when the edit next writes, or ends,
    /// something else changed meanwhile, like a completion settling or a
    /// date picked in the inspector, and the edit's Undo leaves it alone.
    fileprivate var expected: [UUID: EditorBlockRecord]
    fileprivate var expectedAttachments: [UUID: EditorAttachmentRecord]

    fileprivate init(listIDs: Set<UUID>, baseline: EditorSnapshot, touchedIDs: Set<UUID>) {
        self.listIDs = listIDs
        self.baseline = baseline
        self.touchedIDs = touchedIDs
        expected = baseline.blocks
        expectedAttachments = baseline.attachments
    }

    /// Folds into the baseline what changed in `current` since the edit last
    /// wrote. `current` holds every touched block that still exists, unless
    /// `partial`, when it holds only some of them.
    fileprivate func absorbChanges(in current: EditorSnapshot, partial: Bool = false) {
        for id in touchedIDs {
            guard let expected = expected[id] else { continue }
            if let now = current.blocks[id] {
                baseline.blocks[id]?.adopt(changesIn: now, since: expected)
            } else if !partial {
                // Taken away by something else: the edit's Undo doesn't bring it back.
                baseline.blocks[id] = nil
                self.expected[id] = nil
            }
        }
        guard !partial else { return }
        for (id, now) in current.attachments where now.blockID.map(touchedIDs.contains) == true {
            if let expected = expectedAttachments[id] {
                if now != expected { baseline.attachments[id] = now }
            } else if baseline.attachments[id] == nil {
                baseline.attachments[id] = now
            }
        }
        for id in expectedAttachments.keys where current.attachments[id] == nil {
            baseline.attachments[id] = nil
            expectedAttachments[id] = nil
        }
    }

    /// Takes `current` as how the edit left its blocks.
    fileprivate func expect(_ current: EditorSnapshot) {
        for id in touchedIDs { expected[id] = current.blocks[id] }
        expectedAttachments = current.attachments.filter { $0.value.blockID.map(touchedIDs.contains) == true }
    }

    /// A copy to try a commit on, leaving this session as it is.
    fileprivate func copy() -> EditorEditSession {
        let copy = EditorEditSession(listIDs: listIDs, baseline: baseline, touchedIDs: touchedIDs)
        copy.expected = expected
        copy.expectedAttachments = expectedAttachments
        return copy
    }
}

private struct EditorLabelRecord: Equatable {
    var id: UUID
    var name: String
    var accent: String
    var sortIndex: Double
    var createdAt: Date
    init(_ label: TaskLabel) {
        id = label.id
        name = label.name
        accent = label.accentRaw
        sortIndex = label.sortIndex
        createdAt = label.createdAt
    }
}

extension Store {
    /// Registers one inverse for a structural edit with the same window undo
    /// manager used by NSTextView. Native typing undo remains native.
    /// `didRegister` runs once the inverse is on the stack, in the same step.
    func undoableEditorEdit<T>(in listID: UUID, name: String, undoManager: UndoManager?, includingNewLabels: Bool = false,
                               didRegister: (() -> Void)? = nil, _ body: () -> T) -> T {
        undoableEditorEdit(in: Set([listID]), name: name, undoManager: undoManager, includingNewLabels: includingNewLabels,
                           didRegister: didRegister, body)
    }

    func undoableEditorEdit<T>(in listIDs: Set<UUID>, name: String, undoManager: UndoManager?, includingNewLabels: Bool = false,
                               didRegister: (() -> Void)? = nil, _ body: () -> T) -> T {
        guard let undoManager, !isRecordingEditorEdit else { return body() }
        let before = EditorSnapshot(store: self, listIDs: listIDs, includingNewLabels: includingNewLabels)
        isRecordingEditorEdit = true
        editorMediaBackups = [:]
        let result = body()
        let after = EditorSnapshot(store: self, listIDs: listIDs, includingNewLabels: includingNewLabels)
        let media = editorMediaBackups
        isRecordingEditorEdit = false
        editorMediaBackups = [:]
        let changed = before.changedIDs(comparedTo: after)
        guard !changed.blocks.isEmpty || !changed.attachments.isEmpty else { return result }
        (NSApp?.keyWindow?.firstResponder as? NSTextView)?.breakUndoCoalescing()
        undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
            guard let undoManager else { return }
            store.restoreEditorEdit(from: after, to: before, media: media, name: name, undoManager: undoManager)
        }
        undoManager.setActionName(name)
        didRegister?()
        return result
    }

    /// Starts an edit that ``commitEditorSession(_:name:undoManager:)`` will
    /// undo as one step, from how `blockIDs` are now.
    func beginEditorSession(in listID: UUID, covering blockIDs: Set<UUID>) -> EditorEditSession {
        let listIDs = Set([listID])
        return EditorEditSession(listIDs: listIDs,
                                 baseline: EditorSnapshot(store: self, listIDs: listIDs, blockIDs: blockIDs),
                                 touchedIDs: blockIDs)
    }

    /// Runs a structural change as part of `session`, registering no Undo of
    /// its own: whatever it changes, the session's one step restores.
    func recordInEditorSession<T>(_ session: EditorEditSession, _ body: () -> T) -> T {
        guard !isRecordingEditorEdit else { return body() }
        let before = EditorSnapshot(store: self, listIDs: session.listIDs)
        session.absorbChanges(in: before)
        isRecordingEditorEdit = true
        editorMediaBackups = [:]
        let result = body()
        let after = EditorSnapshot(store: self, listIDs: session.listIDs)
        session.media.merge(editorMediaBackups) { first, _ in first }
        isRecordingEditorEdit = false
        editorMediaBackups = [:]
        let changed = before.changedIDs(comparedTo: after)
        let owners = changed.attachments.flatMap { id in
            [before.attachments[id]?.blockID, after.attachments[id]?.blockID].compactMap { $0 }
        }
        // A block's first change in the session is the one its baseline keeps.
        for id in changed.blocks.union(owners) where !session.touchedIDs.contains(id) {
            session.touchedIDs.insert(id)
            session.baseline.blocks[id] = before.blocks[id]
            for (attachmentID, record) in before.attachments where record.blockID == id {
                session.baseline.attachments[attachmentID] = record
            }
        }
        session.expect(after)
        return result
    }

    /// Runs a change the session's own line makes to `block` outside any
    /// structural change, such as its typing, so the session tells it apart
    /// from what anything else changes in that block.
    func writeInEditorSession<T>(_ session: EditorEditSession, to block: Block, _ body: () -> T) -> T {
        let id = block.id
        let live = { block.modelContext != nil && !block.isDeleted }
        guard session.touchedIDs.contains(id), live() else { return body() }
        var current = session.baseline
        current.blocks = [id: EditorBlockRecord(block)]
        session.absorbChanges(in: current, partial: true)
        let result = body()
        if live() { session.expected[id] = EditorBlockRecord(block) }
        return result
    }

    /// Takes the session's blocks as they are now for its baseline. An Undo
    /// or Redo made while the session is open has already been recorded, so
    /// the session must not restore past it.
    func rebaseEditorSession(_ session: EditorEditSession) {
        session.baseline = EditorSnapshot(store: self, listIDs: session.listIDs, blockIDs: session.touchedIDs)
        session.expect(session.baseline)
        session.media = [:]
    }

    /// Registers the session's one Undo, named `name`. `false`, and nothing
    /// registered, when its blocks are back as they began.
    @discardableResult
    func commitEditorSession(_ session: EditorEditSession, name: String, undoManager: UndoManager?) -> Bool {
        let after = EditorSnapshot(store: self, listIDs: session.listIDs, blockIDs: session.touchedIDs)
        session.absorbChanges(in: after)
        let before = session.baseline
        let changed = before.changedIDs(comparedTo: after)
        guard !changed.blocks.isEmpty || !changed.attachments.isEmpty else { return false }
        guard let undoManager else { return true }
        let media = session.media
        undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
            guard let undoManager else { return }
            store.restoreEditorEdit(from: after, to: before, media: media, name: name, undoManager: undoManager)
        }
        undoManager.setActionName(name)
        return true
    }

    /// Whether ``commitEditorSession(_:name:undoManager:)`` would register
    /// an Undo now, leaving the session as it is. `blockIDs`, blocks the
    /// session added that are about to go, are left out as gone.
    func editorSessionHasChanges(_ session: EditorEditSession, excluding blockIDs: Set<UUID> = []) -> Bool {
        let after = EditorSnapshot(store: self, listIDs: session.listIDs,
                                   blockIDs: session.touchedIDs.subtracting(blockIDs))
        let probe = session.copy()
        probe.absorbChanges(in: after)
        let changed = probe.baseline.changedIDs(comparedTo: after)
        return !changed.blocks.isEmpty || !changed.attachments.isEmpty
    }

    /// Copy before the async disk deletion, never after it.
    func removeEditorMedia(filename: String) {
        // Undo needs independent bytes even when another owner keeps the cache
        // today: that owner may remove or replace its media before Undo runs.
        if isRecordingEditorEdit, let data = MediaStore.shared.fileContents(filename: filename) {
            editorMediaBackups[filename] = data
        }
        // An old/shared cache filename can still belong to recoverable content.
        // Retention prevents cache erasure, without skipping the Undo snapshot.
        do {
            if try context.fetch(FetchDescriptor<TaskList>()).contains(where: { !$0.isDeleted && $0.coverFilename == filename }) { return }
            let retained = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID != nil }))
            if retained.contains(where: { $0.mediaFilename == filename }) { return }
            let ids = Set(retained.map(\.id))
            if try context.fetch(FetchDescriptor<Attachment>()).contains(where: {
                $0.filename == filename && $0.blockID.map(ids.contains) == true
            }) { return }
        } catch {
            persistenceError = "A file could not be checked for retained references. It has been kept. \(error.localizedDescription)"
            return
        }
        MediaStore.shared.delete(filename: filename)
    }

    private func restoreEditorEdit(from source: EditorSnapshot, to desired: EditorSnapshot, media: [String: Data], name: String, undoManager: UndoManager) {
        guard desired.listIDs.allSatisfy({ list(id: $0) != nil }) else {
            editorNotice = "This edit cannot be restored because its list is unavailable. Restore the list from Trash first if it was deleted."
            return
        }
        let changed = source.changedIDs(comparedTo: desired)
        let attachmentOwners = Set(changed.attachments.flatMap { id in
            [source.attachments[id]?.blockID, desired.attachments[id]?.blockID].compactMap { $0 }
        })
        let changedIDs = Array(changed.blocks.union(attachmentOwners))
        guard changed.blocks.union(attachmentOwners).isDisjoint(with: permanentlyErasedBlockIDs) else {
            editorNotice = "This edit includes permanently deleted content and cannot be restored."
            return
        }
        if let retainedBlocks = try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { changedIDs.contains($0.id) && $0.trashID != nil })), !retainedBlocks.isEmpty {
            editorNotice = "Restore this content from Trash before undoing an earlier edit."
            return
        }
        // An older move/outdent can depend on an unchanged parent that was
        // deleted later. It may only refer to a live parent, or one restored by
        // this exact Undo; an old snapshot alone is not authority to revive it.
        for id in changed.blocks {
            guard let record = desired.blocks[id], let parentID = record.parentID else { continue }
            let restoredParent = changed.blocks.contains(parentID) ? desired.blocks[parentID] : nil
            let liveParent = block(id: parentID)
            guard (restoredParent != nil && restoredParent?.listID == record.listID)
                || (liveParent != nil && liveParent?.listID == record.listID) else {
                editorNotice = "This edit depends on a parent that is no longer available. Restore the parent from Trash first."
                return
            }
        }
        let sourceFiles = source.files(excluding: permanentlyErasedBlockIDs)
        let desiredFiles = desired.files(excluding: permanentlyErasedBlockIDs)
        var retained = media.filter { sourceFiles.contains($0.key) || desiredFiles.contains($0.key) }
        let canRestoreLabels = source.hasLabelSnapshot && desired.hasLabelSnapshot
        let labelsToRestore = canRestoreLabels ? desired.labels.filter { source.labels[$0.key] == nil } : [:]
        var liveLabels: [TaskLabel] = []
        if !labelsToRestore.isEmpty {
            do { liveLabels = try context.fetch(FetchDescriptor<TaskLabel>()).filter { !$0.isDeleted } }
            catch {
                editorNotice = "The edit could not be restored because its labels could not be read. \(error.localizedDescription)"
                return
            }
        }

        // Save files needed by Redo before deleting anything. The media queue
        // serializes deletion and restoration, avoiding an async unlink race.
        for filename in sourceFiles.subtracting(desiredFiles) {
            if let data = MediaStore.shared.fileContents(filename: filename) { retained[filename] = data }
        }
        do {
            for filename in desiredFiles {
                if let data = retained[filename] {
                    try MediaStore.shared.restoreFile(data, filename: filename)
                }
            }
        } catch {
            persistenceError = "The edit could not be restored: \(error.localizedDescription)"
            return
        }

        let removedBlockIDs = changed.blocks.filter { desired.blocks[$0] == nil }
        if !removedBlockIDs.isEmpty { onEditorBlocksRemoved?(removedBlockIDs) }

        // Only identities introduced by this paste participate. Existing
        // labels and edits made to them after the paste remain independent.
        var restoredLabels: [UUID: UUID] = [:]
        for (id, record) in labelsToRestore {
            if let resolved = resolvedLabelIDs([id]).first, liveLabels.contains(where: { $0.id == resolved }) {
                restoredLabels[id] = resolved
            } else if let existing = liveLabels.first(where: { TaskLabel.namesMatch($0.name, record.name) }) {
                restoredLabels[id] = existing.id
            } else {
                let label = TaskLabel(name: record.name, accent: ListAccent(rawValue: record.accent) ?? .violet, sortIndex: record.sortIndex)
                label.id = id
                label.createdAt = record.createdAt
                context.insert(label)
                liveLabels.append(label)
                restoredLabels[id] = id
            }
        }

        for id in changed.attachments {
            let existing = try? context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })).first
            if let record = desired.attachments[id] {
                let model = existing ?? Attachment(blockID: record.blockID ?? UUID(), filename: record.filename, displayName: record.displayName, contentType: record.contentType, byteCount: record.byteCount)
                if existing == nil { context.insert(model) }
                record.apply(to: model, replacing: existing == nil ? nil : source.attachments[id])
            } else if let existing { context.delete(existing) }
        }
        for id in changed.blocks {
            let existing = block(id: id)
            if let record = desired.blocks[id] {
                let model = existing ?? Block()
                if existing == nil { context.insert(model) }
                record.apply(to: model, replacing: existing == nil ? nil : source.blocks[id])
                if source.blocks[id] == nil, model.isTask {
                    pendingRestoredTaskIDs.insert(id)
                }
                model.labelIDs = resolvedLabelIDs(model.labelIDs.map { restoredLabels[$0] ?? $0 })
                let listID = resolvedListID(model.listID)
                if model.listID != listID { model.listID = listID }
            } else if let existing {
                context.delete(existing)
            }
        }
        let introducedLabels = canRestoreLabels ? source.labels.filter { desired.labels[$0.key] == nil } : [:]
        if !introducedLabels.isEmpty {
            // Cleanup is optional. A failed global reference read cannot mean
            // that an unrelated task has stopped using one of these labels.
            if let references = try? context.fetch(FetchDescriptor<Block>()) {
                let referencedLabels = Set(references.filter { !$0.isDeleted }.flatMap(\.labelIDs))
                for (id, record) in introducedLabels where !referencedLabels.contains(id) {
                    if let label = allLabels().first(where: { $0.id == id }), EditorLabelRecord(label) == record {
                        context.delete(label)
                    }
                }
            }
        }
        if canRestoreLabels, !source.labels.isEmpty || !desired.labels.isEmpty { labelRevision += 1 }
        // Global references include other documents and retained Trash groups.
        // A failed reference read keeps the cache for a later cleanup.
        if let blocks = try? context.fetch(FetchDescriptor<Block>()),
           let files = try? context.fetch(FetchDescriptor<Attachment>()),
           let lists = try? context.fetch(FetchDescriptor<TaskList>()) {
            let referenced = Set(blocks.filter { !$0.isDeleted }.compactMap(\.mediaFilename)
                + files.filter { !$0.isDeleted }.map(\.filename) + lists.filter { !$0.isDeleted }.compactMap(\.coverFilename))
            for filename in sourceFiles.subtracting(desiredFiles).subtracting(referenced) {
                MediaStore.shared.delete(filename: filename)
            }
        }
        save()
        refreshAllReminders()
        undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
            guard let undoManager else { return }
            store.restoreEditorEdit(from: desired, to: source, media: retained, name: name, undoManager: undoManager)
        }
        undoManager.setActionName(name)
    }
}
