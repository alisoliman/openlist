import Foundation
import SwiftData

enum CopyError: LocalizedError {
    case unavailable, ordering
    var errorDescription: String? {
        switch self {
        case .unavailable: "The source is no longer available."
        case .ordering: "There is no space next to this item. Reorder its neighbors and try again."
        }
    }
}

/// Files and detached models are prepared before a single insert transaction.
/// A failed save only rolls back the sibling context, never the live editor.
final class StagedContentCopy {
    let writer: ModelContext
    private var filenames: [String] = []
    private var tasks: [Block] = []
    private var committed = false

    func insert(_ block: Block) {
        writer.insert(block)
        if block.isTask { tasks.append(block) }
    }

    func stageMedia(_ data: Data, fileExtension: String) throws -> String {
        let name = UUID().uuidString + (fileExtension.isEmpty ? "" : "." + fileExtension)
        filenames.append(name)
        try MediaStore.shared.restoreFile(data, filename: name)
        return name
    }

    init(container: ModelContainer) {
        writer = ModelContext(container)
        writer.autosaveEnabled = false
    }

    func discard() {
        guard !committed else { return }
        writer.rollback()
        for filename in filenames { MediaStore.shared.delete(filename: filename) }
    }

    func clone(_ originals: [Block], to listID: UUID, store: Store, mode: CopyMode,
               rootID: UUID? = nil, parentID: UUID? = nil, rootIndex: Double? = nil) throws -> [UUID: UUID] {
        let idMap = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, UUID()) })
        for original in originals {
            let clone = Block(kind: original.kind, listID: listID)
            clone.id = idMap[original.id]!
            clone.parentID = original.id == rootID ? parentID : original.parentID.flatMap { idMap[$0] }
            clone.sortIndex = original.id == rootID ? rootIndex ?? original.sortIndex : original.sortIndex
            clone.copyPayload(from: original)
            mode.apply(to: clone)
            if let filename = original.mediaFilename {
                let copied = try copyFile(filename, data: original.mediaData)
                clone.mediaFilename = copied.name
                clone.mediaData = copied.data
            }
            insert(clone)

            let originalID = original.id
            let attachments = try store.context.fetch(FetchDescriptor<Attachment>(
                predicate: #Predicate { $0.blockID == originalID }, sortBy: [SortDescriptor(\.sortIndex)]))
            for attachment in attachments where !attachment.isDeleted {
                let copied = try copyFile(attachment.filename, data: attachment.contentData)
                let copy = Attachment(blockID: clone.id, filename: copied.name,
                    displayName: attachment.displayName, contentType: attachment.contentType,
                    byteCount: attachment.byteCount, sortIndex: attachment.sortIndex, contentData: copied.data)
                copy.createdAt = attachment.createdAt
                writer.insert(copy)
            }
        }
        return idMap
    }

    private func copyFile(_ filename: String, data: Data?) throws -> (name: String, data: Data) {
        // Read retained bytes directly; materializing the source could rewrite
        // its cache even when this copy subsequently fails.
        let bytes = try data ?? MediaStore.shared.readFile(filename: filename)
        let ext = (filename as NSString).pathExtension
        let name = try stageMedia(bytes, fileExtension: ext)
        return (name, bytes)
    }

    func commit(owningList: TaskList) throws {
        // Copy and its fresh history share one transaction. These are creation
        // facts about the new IDs, never inherited events from the source.
        for task in tasks {
            let event = ActivityEvent(kind: .created, title: task.displayTitle,
                blockID: task.id, listID: task.listID,
                listTitle: owningList.displayTitle, listIcon: owningList.icon)
            event.change = TaskActivityChange(before: nil, after: TaskActivityState(task, list: owningList))
            writer.insert(event)
        }
        try writer.save()
        committed = true
    }
}

extension Store {
    /// Includes mixed descendants at every depth, independent of collapse or
    /// completion visibility. Copying never rewrites the source's fields.
    func copySources(for block: Block) throws -> [Block] {
        guard let current = self.block(id: block.id), !current.isDeleted,
              let listID = current.listID, list(id: listID) != nil else { throw CopyError.unavailable }
        return [current] + BlockTree.descendants(of: current.id, in: blocks(inList: listID))
    }

    @discardableResult
    func copyBlock(_ block: Block, mode: CopyMode) throws -> UUID {
        let originals = try copySources(for: block)
        let source = originals[0]
        guard let listID = resolvedListID(source.listID),
              let owningList = list(id: listID) else { throw CopyError.unavailable }
        let siblings = blocks(inList: listID).filter { $0.parentID == source.parentID && $0.id != source.id }
        let next = siblings.map(\.sortIndex).filter { $0 > source.sortIndex }.min()
        let index = try copyIndex(after: source.sortIndex, before: next)
        let staged = StagedContentCopy(container: context.container)
        defer { staged.discard() }
        let ids = try staged.clone(originals, to: listID, store: self, mode: mode,
            rootID: source.id, parentID: source.parentID, rootIndex: index)
        try staged.commit(owningList: owningList)
        refreshAllReminders()
        onDidSave?()
        return ids[source.id]!
    }

    @discardableResult
    func copyList(_ list: TaskList, mode: CopyMode) throws -> UUID {
        guard let source = self.list(id: list.id), !source.isDeleted else { throw CopyError.unavailable }
        let copy = TaskList(title: "\(source.displayTitle) copy", icon: source.icon, accent: source.accent)
        copy.summary = source.summary
        copy.sectionID = source.sectionID
        copy.isPinned = source.isPinned
        copy.sortingRaw = source.sortingRaw
        copy.showsCompleted = source.showsCompleted
        copy.completedVisibilityRaw = source.completedVisibilityRaw
        copy.availabilityCategoryRaw = source.availabilityCategoryRaw
        let lists = allLists(includeArchived: true)
        copy.sortIndex = try copyIndex(after: source.sortIndex,
            before: lists.map(\.sortIndex).filter { $0 > source.sortIndex }.min())
        copy.sidebarIndex = try copyIndex(after: source.sidebarIndex,
            before: lists.filter { $0.sectionID == source.sectionID }.map(\.sidebarIndex)
                .filter { $0 > source.sidebarIndex }.min())
        let staged = StagedContentCopy(container: context.container)
        defer { staged.discard() }
        staged.writer.insert(copy)
        let listID = source.id
        let originals = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.listID == listID }))
            .filter { !$0.isDeleted }
        _ = try staged.clone(originals, to: copy.id, store: self, mode: mode)
        try staged.commit(owningList: copy)
        refreshAllReminders()
        onDidSave?()
        return copy.id
    }

    private func copyIndex(after source: Double, before next: Double?) throws -> Double {
        let index = BlockTree.index(after: source, before: next)
        guard index.isFinite, index > source, next.map({ index < $0 }) ?? true else { throw CopyError.ordering }
        return index
    }
}
