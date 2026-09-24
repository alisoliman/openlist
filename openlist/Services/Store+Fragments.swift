import AppKit
import SwiftData

extension Store {
    /// An insertion-only sibling transaction. Live drafts, existing task/list
    /// instances and their pending edits are never rolled back or flushed.
    /// A paste is new work: the schedules the fragment carries stay behind.
    ///
    /// The lines go in under the list document's rules (`OutlinePolicy`), as
    /// pasted Markdown's do: beside the anchor line when they can go there,
    /// otherwise beside the line it's under, after the lines already under
    /// that one, stepping out as far as they must. They go under a line only
    /// when it and they are tasks or list items, with what they hold two
    /// levels deep at most. A line the copied hierarchy holds deeper, as an
    /// older outline can, goes beside the one above it at the second level,
    /// in order. Returns the lines at the paste's top level.
    func pasteFragment(_ fragment: DocumentFragment, in document: DocumentContext,
                       after anchorID: UUID?) throws -> [UUID] {
        try fragment.validate()
        guard let listID = resolvedListID(document.listID), let owningList = list(id: listID),
              !owningList.isDeleted else { throw FragmentError.destination }
        let outline = fragment.outline()
        // How many levels each line holds under it.
        var height: [UUID: Int] = [:]
        for (source, _) in outline.reversed() {
            if let parent = source.parentID { height[parent] = max(height[parent] ?? 0, (height[source.id] ?? 0) + 1) }
        }
        let rootBlocks = outline.filter { $0.block.parentID == nil }.map(\.block)
        func fits(under line: Block, at depth: Int) -> Bool {
            OutlinePolicy.nests(line.kind) && rootBlocks.allSatisfy { root in
                BlockKind(rawValue: root.kind).map(OutlinePolicy.nests) == true
                    && depth + (height[root.id] ?? 0) <= OutlinePolicy.maximumDepth
            }
        }
        let parentID: UUID?
        let afterIndex: Double
        // The line the paste goes in after, and how deep its top level is.
        let siblingID: UUID?
        let depth: Int
        if let anchorID {
            guard let anchor = block(id: anchorID), anchor.listID == listID,
                  document.rootBlockID == nil || anchor.parentID == document.rootBlockID
                    || BlockTree.descendants(of: document.rootBlockID!, in: blocks(inList: listID)).contains(where: { $0.id == anchor.id }) else {
                throw FragmentError.destination
            }
            // The anchor and the lines it's under, nearest first, to step out
            // along, never past the document's own root.
            let path = [anchor] + BlockTree.ancestors(of: anchor, in: blocks(inList: listID))
            var step = 0
            while path[step].parentID != document.rootBlockID, step + 1 < path.count,
                  !fits(under: path[step + 1], at: path.count - 1 - step) {
                step += 1
            }
            parentID = path[step].parentID
            afterIndex = path[step].sortIndex
            siblingID = path[step].id
            depth = path.count - 1 - step
        } else {
            parentID = document.rootBlockID
            var parentDepth = -1
            if let parentID {
                guard let parent = block(id: parentID), parent.listID == listID else { throw FragmentError.destination }
                parentDepth = BlockTree.ancestors(of: parent, in: blocks(inList: listID)).count
            }
            afterIndex = children(of: parentID, listID: listID).map(\.sortIndex).max() ?? 0
            siblingID = nil
            depth = parentDepth + 1
        }
        // Where each line goes under the paste's top level: under the line it
        // was copied under while that keeps it two levels deep, or else beside
        // the line above it at the deepest level that does.
        let kept = max(OutlinePolicy.maximumDepth, depth) - depth
        var placedParent: [UUID: UUID] = [:]
        for (source, level) in outline {
            guard let parent = source.parentID else { continue }
            placedParent[source.id] = level <= kept ? parent : placedParent[parent]
        }
        let placedRoots = outline.map(\.block.id).filter { placedParent[$0] == nil }
        let next = children(of: parentID, listID: listID).map(\.sortIndex).filter { $0 > afterIndex }.min()
        var index = afterIndex
        var positions: [UUID: Double] = [:]
        for root in placedRoots {
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
        if let siblingID {
            guard let saved = savedByID[siblingID], saved.parentID == parentID, saved.sortIndex == afterIndex else {
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
                throw FragmentError.invalid("A label has an invalid name or colour.")
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
        for (source, _) in outline {
            let clone = Block(kind: BlockKind(rawValue: source.kind)!, text: source.text, listID: listID)
            clone.id = ids[source.id]!
            clone.parentID = placedParent[source.id].flatMap { ids[$0] } ?? parentID
            if let position = positions[source.id] { clone.sortIndex = position }
            else if let parent = placedParent[source.id] {
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
        return placedRoots.map { ids[$0]! }
    }
}

private extension DocumentFragment {
    /// The lines in document order, each with how many levels under its root
    /// it is: a root, then what's under it, as a document lists them.
    func outline() -> [(block: FragmentBlock, level: Int)] {
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let children = Dictionary(grouping: blocks.filter { $0.parentID != nil }, by: { $0.parentID! })
        var result: [(block: FragmentBlock, level: Int)] = []
        var stack = roots.reversed().compactMap { byID[$0] }.map { (block: $0, level: 0) }
        while let line = stack.popLast() {
            result.append(line)
            stack += (children[line.block.id] ?? []).reversed().map { (block: $0, level: line.level + 1) }
        }
        return result
    }
}
