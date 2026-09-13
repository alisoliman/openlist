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

    init(store: Store, listIDs: Set<UUID>) {
        self.listIDs = Set(listIDs.map { store.resolvedListID($0) ?? $0 })
        let models = self.listIDs.flatMap { store.blocks(inList: $0) }
        blocks = Dictionary(uniqueKeysWithValues: models.map { ($0.id, EditorBlockRecord($0)) })
        attachments = Dictionary(uniqueKeysWithValues: models.flatMap { store.attachments(for: $0.id) }.map { ($0.id, EditorAttachmentRecord($0)) })
    }

    var files: Set<String> {
        Set(blocks.values.compactMap(\.mediaFilename) + attachments.values.map(\.filename))
    }

    func changedIDs(comparedTo other: Self) -> (blocks: Set<UUID>, attachments: Set<UUID>) {
        (Set(blocks.keys).union(other.blocks.keys).filter { blocks[$0] != other.blocks[$0] },
         Set(attachments.keys).union(other.attachments.keys).filter { attachments[$0] != other.attachments[$0] })
    }
}

extension Store {
    /// Registers one inverse for a structural edit with the same window undo
    /// manager used by NSTextView. Native typing undo remains native.
    func undoableEditorEdit<T>(in listID: UUID, name: String, undoManager: UndoManager?, _ body: () -> T) -> T {
        undoableEditorEdit(in: Set([listID]), name: name, undoManager: undoManager, body)
    }

    func undoableEditorEdit<T>(in listIDs: Set<UUID>, name: String, undoManager: UndoManager?, _ body: () -> T) -> T {
        guard let undoManager, !isRecordingEditorEdit else { return body() }
        let before = EditorSnapshot(store: self, listIDs: listIDs)
        isRecordingEditorEdit = true
        editorMediaBackups = [:]
        let result = body()
        let after = EditorSnapshot(store: self, listIDs: listIDs)
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
        return result
    }

    /// Copy before the async disk deletion, never after it.
    func removeEditorMedia(filename: String) {
        if isRecordingEditorEdit, let data = MediaStore.shared.fileContents(filename: filename) {
            editorMediaBackups[filename] = data
        }
        MediaStore.shared.delete(filename: filename)
    }

    private func restoreEditorEdit(from source: EditorSnapshot, to desired: EditorSnapshot, media: [String: Data], name: String, undoManager: UndoManager) {
        guard desired.listIDs.allSatisfy({ list(id: $0) != nil }) else {
            editorNotice = "This edit cannot be restored because its list was permanently deleted."
            return
        }
        let changed = source.changedIDs(comparedTo: desired)
        var retained = media

        // Save files needed by Redo before deleting anything. The media queue
        // serializes deletion and restoration, avoiding an async unlink race.
        for filename in source.files.subtracting(desired.files) {
            if let data = MediaStore.shared.fileContents(filename: filename) { retained[filename] = data }
        }
        do {
            for filename in desired.files {
                if let data = retained[filename] {
                    try MediaStore.shared.restoreFile(data, filename: filename)
                }
            }
        } catch {
            persistenceError = "The edit could not be restored: \(error.localizedDescription)"
            return
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
                model.labelIDs = resolvedLabelIDs(model.labelIDs)
                let listID = resolvedListID(model.listID)
                if model.listID != listID { model.listID = listID }
            } else if let existing {
                NotificationService.shared.cancelReminder(for: id)
                context.delete(existing)
            }
        }
        for filename in source.files.subtracting(desired.files) { MediaStore.shared.delete(filename: filename) }
        save()
        refreshAllReminders()
        undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
            guard let undoManager else { return }
            store.restoreEditorEdit(from: desired, to: source, media: retained, name: name, undoManager: undoManager)
        }
        undoManager.setActionName(name)
    }
}
