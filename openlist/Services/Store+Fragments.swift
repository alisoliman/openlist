import AppKit
import SwiftData

extension Store {
    /// An insertion-only sibling transaction. Live drafts, existing task/list
    /// instances and their pending edits are never rolled back or flushed.
    /// A paste is new work: the schedules the fragment carries stay behind.
    func pasteFragment(_ fragment: DocumentFragment, in document: DocumentContext,
                       after anchorID: UUID?) throws -> [UUID] {
        try fragment.validate()
        guard let listID = resolvedListID(document.listID), let owningList = list(id: listID),
              !owningList.isDeleted else { throw FragmentError.destination }
        let parentID: UUID?
        let afterIndex: Double
        if let anchorID {
            guard let anchor = block(id: anchorID), anchor.listID == listID,
                  document.rootBlockID == nil || anchor.parentID == document.rootBlockID
                    || BlockTree.descendants(of: document.rootBlockID!, in: blocks(inList: listID)).contains(where: { $0.id == anchor.id }) else {
                throw FragmentError.destination
            }
            parentID = anchor.parentID
            afterIndex = anchor.sortIndex
        } else {
            parentID = document.rootBlockID
            if let parentID {
                guard let parent = block(id: parentID), parent.listID == listID else { throw FragmentError.destination }
            }
            afterIndex = children(of: parentID, listID: listID).map(\.sortIndex).max() ?? 0
        }
        let next = children(of: parentID, listID: listID).map(\.sortIndex).filter { $0 > afterIndex }.min()
        var index = afterIndex
        var positions: [UUID: Double] = [:]
        for root in fragment.roots {
            let value = BlockTree.index(after: index, before: next)
            guard value.isFinite, value > index, next.map({ value < $0 }) ?? true else { throw CopyError.ordering }
            positions[root] = value
            index = value
        }

        let staged = StagedContentCopy(container: context.container)
        defer { staged.discard() }
        guard try staged.writer.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == listID })).first != nil else {
            throw FragmentError.destination
        }
        let savedBlocks = try staged.writer.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.listID == listID }))
        let savedByID = Dictionary(savedBlocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let anchorID {
            guard let saved = savedByID[anchorID], saved.parentID == parentID, saved.sortIndex == afterIndex else {
                throw FragmentError.destination
            }
        }
        var ancestry = Set<UUID>()
        var ancestor = parentID
        while let id = ancestor {
            guard ancestry.insert(id).inserted, let saved = savedByID[id] else { throw FragmentError.destination }
            ancestor = saved.parentID
        }
        if let rootID = document.rootBlockID, !ancestry.contains(rootID) { throw FragmentError.destination }
        var existingLabels = try staged.writer.fetch(FetchDescriptor<TaskLabel>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))
        var labelMap: [UUID: UUID] = [:]
        for definition in fragment.labels {
            let name = TaskLabel.normalize(definition.name)
            guard !name.isEmpty, let accent = ListAccent(rawValue: definition.accent) else {
                throw FragmentError.invalid("A label has an invalid name or color.")
            }
            let matches = existingLabels.filter { TaskLabel.namesMatch($0.name, name) }.sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }
            if let existing = matches.first {
                labelMap[definition.id] = existing.id
            } else {
                let label = TaskLabel(name: name, accent: accent,
                    sortIndex: (existingLabels.map(\.sortIndex).max() ?? 0) + BlockTree.indexStep)
                staged.writer.insert(label)
                existingLabels.append(label)
                labelMap[definition.id] = label.id
            }
        }
        let ids = Dictionary(uniqueKeysWithValues: fragment.blocks.map { ($0.id, UUID()) })
        var childIndices: [UUID: Double] = [:]
        for source in fragment.blocks {
            let clone = Block(kind: BlockKind(rawValue: source.kind)!, text: source.text, listID: listID)
            clone.id = ids[source.id]!
            clone.parentID = source.parentID.flatMap { ids[$0] } ?? parentID
            if let position = positions[source.id] { clone.sortIndex = position }
            else if let parent = source.parentID {
                let value = (childIndices[parent] ?? 0) + BlockTree.indexStep
                childIndices[parent] = value
                clone.sortIndex = value
            }
            clone.richData = RichTextCodec.encode(FragmentContent.attributedText(source))
            clone.isCollapsed = source.isCollapsed
            clone.isCompleted = source.isCompleted
            clone.completedAt = source.completedAt
            clone.isStarred = source.isStarred
            clone.priorityRaw = source.priority
            clone.labelIDs = Array(Set(source.labelIDs.compactMap { labelMap[$0] })).sorted { $0.uuidString < $1.uuidString }
            clone.note = source.note
            clone.schedulingEstimateMinutes = source.schedulingEstimateMinutes
            clone.keepsSessionsTogether = source.keepsSessionsTogether
            clone.tracksAwayFromMac = source.tracksAwayFromMac
            // Dates, reminders, repeats, day selections and deferrals stay behind.
            // Occurrence IDs, work sessions, placements and prior history are
            // deliberately absent from the clipboard contract.
            if let media = source.image {
                clone.mediaFilename = try staged.stageMedia(media.data, fileExtension: media.fileExtension)
                clone.mediaData = media.data
            }
            clone.mediaWidth = source.mediaWidth
            clone.mediaHeight = source.mediaHeight
            clone.mediaCaption = source.mediaCaption
            staged.insert(clone)
            for (offset, file) in source.attachments.enumerated() {
                let filename = try staged.stageMedia(file.media.data, fileExtension: file.media.fileExtension)
                staged.writer.insert(Attachment(blockID: clone.id, filename: filename,
                    displayName: file.displayName, contentType: file.contentType,
                    byteCount: file.media.data.count, sortIndex: Double(offset) * BlockTree.indexStep,
                    contentData: file.media.data))
            }
        }
        try staged.commit(owningList: owningList)
        refreshAllReminders()
        onDidSave?()
        return fragment.roots.map { ids[$0]! }
    }
}
