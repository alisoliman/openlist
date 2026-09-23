import Foundation
import SwiftData

enum TrashError: LocalizedError {
    case unavailable, invalidRetention
    var errorDescription: String? {
        switch self {
        case .unavailable: "This item is no longer available. Refresh Trash and try again."
        case .invalidRetention: "This Trash item has incomplete recovery information. Keep it and try a compatible app version."
        }
    }
}

extension Store {
    func trashEntries() throws -> [TrashEntry] {
        let lists = try context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.trashID != nil }))
        let blocks = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID != nil }))
        let attachments = try context.fetch(FetchDescriptor<Attachment>())
        func entry(id: UUID, title: String, isList: Bool, metadata: TrashMetadata?) -> TrashEntry {
            let members = blocks.filter { $0.trashID == id }
            let ids = Set(members.map(\.id))
            var media: [String: Int] = [:]
            for list in lists where list.trashID == id {
                if let name = list.coverFilename { media[name] = list.coverData?.count ?? list.coverMetadata?.byteCount ?? 0 }
            }
            for block in members {
                if let name = block.mediaFilename { media[name] = block.mediaData?.count ?? 0 }
            }
            for file in attachments where file.blockID.map(ids.contains) == true {
                media[file.filename] = file.contentData?.count ?? file.byteCount
            }
            return TrashEntry(id: id, title: title, isList: isList, metadata: metadata,
                blockCount: members.count, byteCount: media.values.reduce(0, +), listCount: lists.filter { $0.trashID == id }.count)
        }
        return (lists.filter { $0.trashID == $0.id }.map {
            entry(id: $0.id, title: $0.displayTitle, isList: true, metadata: $0.trashMetadata)
        } + blocks.filter { $0.trashID == $0.id }.map {
            entry(id: $0.id, title: $0.displayTitle, isList: false, metadata: $0.trashMetadata)
        }).sorted { ($0.metadata?.deletedAt ?? .distantPast) > ($1.metadata?.deletedAt ?? .distantPast) }
    }

    /// Selection spans documents. A selected ancestor owns its selected descendants.
    /// Explicit deletion is its own Undo operation, outside structural snapshots.
    @discardableResult
    func trashBlocks(_ selection: [Block], undoManager: UndoManager? = nil) -> Bool {
        var rootIDs: [UUID] = []
        var removedIDs = Set<UUID>()
        let succeeded = trashTransaction("Content could not be moved to Trash", scope: .subtrees(Set(selection.map(\.id)))) {
            let selected = Set(selection.map(\.id))
            let all = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil }))
            let currentIDs = Set(all.map(\.id))
            guard !selected.isEmpty, selected.isSubset(of: currentIDs) else { throw TrashError.unavailable }
            var covered = Set<UUID>()
            for row in BlockTree.flatten(all, respectCollapse: false) where selected.contains(row.id) && !covered.contains(row.id) {
                let root = row.block
                let members = [root] + BlockTree.descendants(of: root.id, in: all.filter { $0.listID == root.listID })
                covered.formUnion(members.map(\.id))
                removedIDs.formUnion(members.map(\.id))
                rootIDs.append(root.id)
                let metadata = deletionMetadata(for: members, list: list(id: root.listID), parent: block(id: root.parentID))
                root.trashMetadataData = try JSONEncoder().encode(metadata)
                try retain(members, groupID: root.id)
            }
            guard !rootIDs.isEmpty else { throw TrashError.unavailable }
        }
        if succeeded {
            trashNotice = nil
            onEditorBlocksRemoved?(removedIDs)
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
                    // Content erased since is gone for good; Undo restores the rest.
                    let remaining = rootIDs.filter { !store.permanentlyErasedBlockIDs.contains($0) }
                    guard !remaining.isEmpty else { return }
                    if store.restoreTrash(ids: remaining), let undoManager {
                        undoManager.registerUndo(withTarget: store) { [weak undoManager] store in
                            _ = store.trashBlocks(remaining.compactMap { store.block(id: $0) }, undoManager: undoManager)
                        }
                        undoManager.setActionName("Move to Trash")
                    }
                }
                undoManager.setActionName("Move to Trash")
            }
        }
        return succeeded
    }

    @discardableResult
    func trashList(_ list: TaskList) -> Bool {
        let owned = listHierarchy().subtree(of: list.id)
        let ownedIDs = Set(owned.map(\.id))
        var removedIDs = Set<UUID>()
        let succeeded = trashTransaction("The list could not be moved to Trash", scope: .lists(ownedIDs)) {
            guard !list.isSystemInbox, !list.isEffectivelyTrashed, !list.isDeleted else { throw TrashError.unavailable }
            let members = try context.fetch(FetchDescriptor<Block>()).filter { !$0.isTrashed && $0.listID.map(ownedIDs.contains) == true }
            removedIDs = Set(members.map(\.id))
            var metadata = deletionMetadata(for: members, list: list, parent: nil)
            metadata.listTitle = listHierarchy().path(for: list.id)
            list.trashMetadataData = try JSONEncoder().encode(metadata)
            for child in owned {
                try retainCover(child)
                child.trashID = list.id
            }
            try retain(members, groupID: list.id)
            log(.listDeleted, title: list.displayTitle, list: list)
        }
        if succeeded {
            trashNotice = nil
            onEditorBlocksRemoved?(removedIDs)
        }
        return succeeded
    }

    private func retainCover(_ list: TaskList) throws {
        if let cover = try list.validatedCover(), list.coverData == nil {
            let bytes = try MediaStore.shared.readFile(filename: cover.filename)
            guard bytes.count == cover.metadata.byteCount else { throw ListCoverError.unavailable }
            trashMediaRollbacks.append { list.coverData = nil }
            list.coverData = bytes
        }
    }

    /// A sync batch may deliver a child or its blocks after the owning parent
    /// reached Trash. Persist their bytes and group membership before recovery
    /// or erasure; a failed read/save leaves all source records intact.
    @discardableResult
    func reconcileRetainedListDescendants() -> Bool {
        let lists: [TaskList], blocks: [Block]
        do {
            lists = try context.fetch(FetchDescriptor<TaskList>())
            blocks = try context.fetch(FetchDescriptor<Block>())
        } catch { trashError = error.localizedDescription; return false }
        let hierarchy = ListHierarchy(lists)
        let arrivingLists = lists.filter { !$0.isTrashed && hierarchy.retainedGroup(for: $0.id) != nil }
        let arrivingBlocks = blocks.filter { !$0.isTrashed && $0.listID.flatMap { hierarchy.retainedGroup(for: $0) } != nil }
        guard !arrivingLists.isEmpty || !arrivingBlocks.isEmpty else { return true }
        let groups = Set(arrivingLists.compactMap { hierarchy.retainedGroup(for: $0.id) }
            + arrivingBlocks.compactMap { $0.listID.flatMap { hierarchy.retainedGroup(for: $0) } })
        return trashTransaction("Synced child documents could not be retained in Trash") {
            for group in groups {
                guard let root = lists.first(where: { $0.id == group && $0.trashID == group }),
                      var metadata = root.trashMetadata else { throw TrashError.invalidRetention }
                let childLists = arrivingLists.filter { hierarchy.retainedGroup(for: $0.id) == group }
                let members = arrivingBlocks.filter { $0.listID.flatMap { hierarchy.retainedGroup(for: $0) } == group }
                let captured = deletionMetadata(for: members, list: root, parent: nil)
                let prior = Set(metadata.labels.map(\.id))
                metadata.labels += captured.labels.filter { !prior.contains($0.id) }
                root.trashMetadataData = try JSONEncoder().encode(metadata)
                for child in childLists { try retainCover(child); child.trashID = group }
                try retain(members, groupID: group)
            }
        }
    }

    private func deletionMetadata(for members: [Block], list: TaskList?, parent: Block?) -> TrashMetadata {
        let labelIDs = Set(members.flatMap(\.labelIDs))
        // The icon the list shows: Inbox always shows its own, whatever it stores.
        return TrashMetadata(deletedAt: .now, listTitle: list?.displayTitle ?? "Unavailable list",
            listIcon: list.map { $0.isSystemInbox ? "📥" : $0.icon },
            parentTitle: parent?.displayTitle, labels: allLabels().filter { labelIDs.contains($0.id) }.map { TrashLabel(id: $0.id, name: $0.name, accentRaw: $0.accentRaw, sortIndex: $0.sortIndex, createdAt: $0.createdAt) })
    }

    private func retain(_ members: [Block], groupID: UUID) throws {
        // Keep bytes in the durable models too; cache cleanup or a failed erase
        // must never make a retained item dependent on a file that disappeared.
        for block in members {
            if let name = block.mediaFilename, block.mediaData == nil {
                let bytes = try MediaStore.shared.readFile(filename: name)
                trashMediaRollbacks.append { block.mediaData = nil }
                block.mediaData = bytes
            }
            for attachment in attachments(for: block.id) where attachment.contentData == nil {
                let bytes = try MediaStore.shared.readFile(filename: attachment.filename)
                trashMediaRollbacks.append { attachment.contentData = nil }
                attachment.contentData = bytes
            }
            pauseWorkSessions(for: block, reason: "Moved to Trash")
            block.trashID = groupID
        }
    }

    /// A label merge may replace the IDs captured at deletion. Before a
    /// referenced label is deleted, retain its current identity and name in
    /// every affected deletion root. Older captured labels remain for merge Undo.
    func preserveTrashLabel(_ label: TaskLabel, referencedBy blocks: [Block]) throws {
        let groups = Array(Set(blocks.filter { $0.isTrashed && $0.labelIDs.contains(label.id) }.compactMap(\.trashID)))
        guard !groups.isEmpty else { return }
        let roots = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { groups.contains($0.id) }))
        let lists = try context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { groups.contains($0.id) }))
        var updates: [() -> Void] = []
        for group in groups {
            let root = roots.first { $0.id == group && $0.trashID == group }
            let list = lists.first { $0.id == group && $0.trashID == group }
            guard var metadata = root?.trashMetadata ?? list?.trashMetadata else { throw TrashError.invalidRetention }
            metadata.labels.removeAll { $0.id == label.id }
            metadata.labels.append(TrashLabel(id: label.id, name: label.name, accentRaw: label.accentRaw,
                sortIndex: label.sortIndex, createdAt: label.createdAt))
            let bytes = try JSONEncoder().encode(metadata)
            updates.append { if let root { root.trashMetadataData = bytes } else { list?.trashMetadataData = bytes } }
        }
        for update in updates { update() }
    }

    /// Preview uses the same ownership checks as restore, before the user acts.
    func trashRestoreDestination(_ entry: TrashEntry) -> String {
        if entry.isList {
            guard let root = try? context.fetch(FetchDescriptor<TaskList>()).first(where: { $0.id == entry.id }) else { return "Restore list" }
            if let parentID = root.parentListID, list(id: parentID) == nil {
                return "Restore list and child documents at top level — original parent is unavailable"
            }
            return "Restore list and child documents"
        }
        let id = entry.id
        guard let root = try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })).first,
              let owner = list(id: root.listID), root.parentID == nil || block(id: root.parentID)?.listID == owner.id else {
            return "Restore to Recovered items — original parent or list is unavailable"
        }
        return "Restore to \(entry.metadata?.formerLocation ?? owner.displayTitle)"
    }

    /// Whether `id` is still in Trash as an entry of its own. An older Redo
    /// checks first: the entry may have been erased or restored since.
    func isInTrash(_ id: UUID) -> Bool {
        let lists = (try? context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id }))) ?? []
        let blocks = (try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == id }))) ?? []
        return lists.contains { $0.trashID == id } || blocks.contains { $0.trashID == id }
    }

    @discardableResult
    func restoreTrash(ids: [UUID]) -> Bool {
        // Feedback from an earlier restore never describes this one.
        trashNotice = nil
        guard reconcileRetainedListDescendants() else { return false }
        var notices: [String] = []
        let succeeded = trashTransaction("Content could not be restored; it remains in Trash", scope: .groups(Set(ids))) {
            let allBlocks = try context.fetch(FetchDescriptor<Block>())
            let allLists = try context.fetch(FetchDescriptor<TaskList>())
            // Restore lists first so a separately retained child can recover its parent.
            let ordered = Set(ids).sorted { a, b in
                let al = allLists.contains { $0.id == a && $0.trashID == a }
                let bl = allLists.contains { $0.id == b && $0.trashID == b }
                return al != bl ? al : a.uuidString < b.uuidString
            }
            for id in ordered {
                let members = allBlocks.filter { $0.trashID == id }
                let retainedList = allLists.first { $0.id == id && $0.trashID == id }
                let root = members.first { $0.id == id }
                guard retainedList != nil || root != nil else { throw TrashError.unavailable }
                guard var metadata = retainedList?.trashMetadata ?? root?.trashMetadata else { throw TrashError.invalidRetention }
                if let retainedList {
                    let retainedLists = allLists.filter { $0.trashID == id }
                    let unitIDs = Set(retainedLists.map(\.id))
                    if let parentID = retainedList.parentListID, !unitIDs.contains(parentID),
                       !allLists.contains(where: { $0.id == parentID && ($0.trashID == nil || ids.contains($0.trashID!)) }) {
                        retainedList.parentListID = nil
                        metadata.recoveryNote = "Restored from \(metadata.formerLocation). Its parent list is unavailable; the list is now at top level."
                    }
                    for child in retainedLists {
                        if let cover = try child.validatedCover() {
                            _ = try MediaStore.shared.materialize(filename: cover.filename, data: child.coverData)
                        }
                        if let sectionID = child.sectionID, !allSections().contains(where: { $0.id == resolvedSectionID(sectionID) }) {
                            child.sectionID = defaultSection()?.id
                            child.isPinned = true
                            if metadata.recoveryNote == nil {
                                metadata.recoveryNote = "Restored from \(metadata.formerLocation). An unavailable sidebar section was replaced with My lists."
                            }
                        }
                        child.trashID = nil
                    }
                } else if let root {
                    let owner = list(id: root.listID)
                    let parent = block(id: root.parentID)
                    if owner == nil || (root.parentID != nil && parent?.listID != owner?.id) {
                        let recovery = TaskList(title: "Recovered items", icon: "🛟", accent: .orange)
                        recovery.summary = "Content restored from an unavailable location. Each recovered item keeps its former location."
                        recovery.isPinned = true
                        recovery.sectionID = defaultSection()?.id
                        recovery.sortIndex = (allLists.map(\.sortIndex).max() ?? 0) + BlockTree.indexStep
                        recovery.sidebarIndex = (allLists.map(\.sidebarIndex).max() ?? 0) + BlockTree.indexStep
                        context.insert(recovery)
                        for member in members { member.listID = recovery.id }
                        root.parentID = nil
                        metadata.recoveryNote = "Recovered from \(metadata.formerLocation). The original parent or list is unavailable."
                        notices.append("\(root.displayTitle) restored to Recovered items from \(metadata.formerLocation).")
                    }
                }
                var labels = allLabels()
                for record in metadata.labels where members.contains(where: { $0.labelIDs.contains(record.id) }) {
                    if let resolved = resolvedLabelIDs([record.id]).first, labels.contains(where: { $0.id == resolved }) {
                        if resolved != record.id { for member in members { member.labelIDs = member.labelIDs.map { $0 == record.id ? resolved : $0 } } }
                    } else if let existing = labels.first(where: { TaskLabel.namesMatch($0.name, record.name) }) {
                        for member in members { member.labelIDs = member.labelIDs.map { $0 == record.id ? existing.id : $0 } }
                    } else {
                        let label = TaskLabel(name: record.name, accent: ListAccent(rawValue: record.accentRaw) ?? .violet, sortIndex: record.sortIndex)
                        label.id = record.id
                        label.createdAt = record.createdAt
                        context.insert(label)
                        labels.append(label)
                    }
                }
                let availableLabels = Set(labels.map(\.id))
                guard members.allSatisfy({ Set($0.labelIDs).isSubset(of: availableLabels) }) else { throw TrashError.invalidRetention }
                for member in members {
                    if let filename = member.mediaFilename {
                        _ = try MediaStore.shared.materialize(filename: filename, data: member.mediaData)
                    }
                    for file in attachments(for: member.id) {
                        _ = try MediaStore.shared.materialize(filename: file.filename, data: file.contentData)
                    }
                    member.trashID = nil
                    if member.isTask { pendingRestoredTaskIDs.insert(member.id) }
                }
                if let retainedList { retainedList.trashMetadataData = try JSONEncoder().encode(metadata) }
                else { root?.trashMetadataData = try JSONEncoder().encode(metadata) }
                if let note = metadata.recoveryNote, notices.isEmpty { notices.append(note) }
                if notices.isEmpty {
                    let owner = retainedList ?? root.flatMap { list(id: $0.listID) }
                    if let owner, owner.isEffectivelyArchived {
                        notices.append("Restored to archived list “\(owner.displayTitle)”. Open Lists and choose Show Archived to view it.")
                    } else if let owner {
                        notices.append("Restored to “\(owner.displayTitle)”.")
                    }
                }
            }
        }
        if succeeded { trashNotice = notices.isEmpty ? "Restored from Trash." : notices.joined(separator: "\n") }
        return succeeded
    }

    /// The UI must confirm this action. No timer or retention period calls it.
    @discardableResult
    func permanentlyEraseTrash(ids: [UUID]) -> Bool {
        trashNotice = nil
        guard reconcileRetainedListDescendants() else { return false }
        var erasedBlockIDs = Set<UUID>()
        let succeeded = trashTransaction("Permanent deletion failed; the retained content can still be restored", scope: .groups(Set(ids))) {
            let groups = Set(ids)
            let all = try context.fetch(FetchDescriptor<Block>())
            let members = all.filter { $0.trashID.map(groups.contains) == true }
            let memberIDs = Set(members.map(\.id))
            erasedBlockIDs = memberIDs
            let allLists = try context.fetch(FetchDescriptor<TaskList>())
            let lists = allLists.filter { $0.trashID.map(groups.contains) == true }
            guard Set(lists.filter { $0.trashID == $0.id }.map(\.id) + members.filter { $0.trashID == $0.id }.map(\.id)) == groups else { throw TrashError.unavailable }
            let files = try context.fetch(FetchDescriptor<Attachment>())
            let removedFiles = files.filter { $0.blockID.map(memberIDs.contains) == true }
            guard members.allSatisfy({ $0.mediaFilename == nil || $0.mediaData != nil }),
                  lists.allSatisfy({ $0.coverFilename == nil || $0.coverData != nil }),
                  removedFiles.allSatisfy({ $0.contentData != nil }) else { throw TrashError.invalidRetention }
            let names = Set(members.compactMap(\.mediaFilename) + removedFiles.map(\.filename) + lists.compactMap(\.coverFilename))
            let referenced = Set(all.filter { !memberIDs.contains($0.id) }.compactMap(\.mediaFilename)
                + files.filter { $0.blockID.map(memberIDs.contains) != true }.map(\.filename)
                + allLists.filter { $0.trashID.map(groups.contains) != true }.compactMap(\.coverFilename))
            // Bytes were committed by retain(). Erase caches first: if unlink or
            // the following save fails, the record remains fully recoverable.
            for name in names.subtracting(referenced) { try MediaStore.shared.eraseCachedFile(filename: name) }
            for file in removedFiles { context.delete(file) }
            for block in members { context.delete(block) }
            for list in lists { context.delete(list) }
        }
        if succeeded { permanentlyErasedBlockIDs.formUnion(erasedBlockIDs) }
        return succeeded
    }

    /// Settings already confirms Delete everything. Retain first so any failed
    /// permanent erase leaves recoverable content, then clear the whole library.
    @discardableResult
    func permanentlyResetLibrary() -> Bool {
        for list in allLists(includeArchived: true) where !list.isSystemInbox && !list.isTrashed {
            guard trashList(list) else { return false }
        }
        if let inbox = inboxList() {
            let content = blocks(inList: inbox.id)
            if !content.isEmpty, !trashBlocks(content) { return false }
        }
        do {
            let ids = try trashEntries().map(\.id)
            if !ids.isEmpty, !permanentlyEraseTrash(ids: ids) { return false }
        } catch { trashError = error.localizedDescription; return false }
        return trashTransaction("The library reset could not finish") {
            for label in try context.fetch(FetchDescriptor<TaskLabel>()) { context.delete(label) }
            for event in try context.fetch(FetchDescriptor<ActivityEvent>()) { context.delete(event) }
            for session in try context.fetch(FetchDescriptor<WorkSession>()) { context.delete(session) }
            for completion in try context.fetch(FetchDescriptor<CompletionRecord>()) { context.delete(completion) }
            for placement in try context.fetch(FetchDescriptor<SchedulePlacement>()) { context.delete(placement) }
        }
    }

    /// Preflight commits unrelated typing. Rollback then covers only this
    /// operation and prevents publishing a successful partial deletion/restore.
    private func trashTransaction(_ message: String, scope: TrashMutationScope = .all, _ body: () throws -> Void) -> Bool {
        do { try persistChanges() }
        catch { trashError = "\(message). Save the current edits and try again. \(error.localizedDescription)"; return false }
        let recovery: TrashMutationSnapshot
        do { recovery = try TrashMutationSnapshot(context: context, scope: scope) }
        catch { trashError = "\(message). \(error.localizedDescription)"; return false }
        trashMediaRollbacks = []
        defer { trashMediaRollbacks = [] }
        var attemptedInsertions: [any PersistentModel] = []
        do {
            try body()
            // A real rejected save can clear insertedModelsArray while keeping
            // those identities in fetch caches. Capture them before the attempt.
            attemptedInsertions = context.insertedModelsArray
            try persistChanges()
            trashError = nil
            return true
        } catch {
            let inserted = attemptedInsertions + context.insertedModelsArray
            let listIDs = inserted.compactMap { ($0 as? TaskList)?.id }
            let labelIDs = inserted.compactMap { ($0 as? TaskLabel)?.id }
            context.rollback()
            recovery.restore()
            for restoreMedia in trashMediaRollbacks { restoreMedia() }
            for model in inserted where model.modelContext != nil { context.delete(model) }
            if let lists = try? context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { listIDs.contains($0.id) })) {
                for list in lists { context.delete(list) }
            }
            if let labels = try? context.fetch(FetchDescriptor<TaskLabel>(predicate: #Predicate { labelIDs.contains($0.id) })) {
                for label in labels { context.delete(label) }
            }
            pendingActivity.removeAll()
            pendingRestoredTaskIDs.removeAll()
            context.processPendingChanges()
            trashError = "\(message). \(error.localizedDescription)"
            return false
        }
    }
}

/// SwiftData rollback can leave retained view instances with attempted values.
/// Restore every field this transaction owns on those same objects as well.
private enum TrashMutationScope {
    case subtrees(Set<UUID>), lists(Set<UUID>), groups(Set<UUID>), all
}

private struct TrashMutationSnapshot {
    private let restoreModels: () -> Void

    init(context: ModelContext, scope: TrashMutationScope) throws {
        // Hierarchy reads are scalar-only. Never materialize unrelated external
        // blobs just to delete one item; only retain() records changed nil bytes.
        let all = try context.fetch(FetchDescriptor<Block>())
        let affected: [Block]
        let affectedLists: [TaskList]
        switch scope {
        case let .subtrees(ids):
            let live = all.filter { !$0.isTrashed && !$0.isDeleted }
            let selected = live.filter { ids.contains($0.id) }
            var included = ids
            for root in selected { included.formUnion(BlockTree.descendants(of: root.id, in: live.filter { $0.listID == root.listID }).map(\.id)) }
            affected = live.filter { included.contains($0.id) }
            affectedLists = []
        case let .lists(ids):
            affected = all.filter { !$0.isTrashed && $0.listID.map(ids.contains) == true }
            affectedLists = try context.fetch(FetchDescriptor<TaskList>()).filter { ids.contains($0.id) }
        case let .groups(ids):
            affected = all.filter { $0.trashID.map(ids.contains) == true }
            affectedLists = try context.fetch(FetchDescriptor<TaskList>()).filter { $0.trashID.map(ids.contains) == true }
        case .all:
            affected = all
            affectedLists = try context.fetch(FetchDescriptor<TaskList>())
        }
        let blocks = affected.map { block in
            let id = block.trashID, metadata = block.trashMetadataData, list = block.listID, parent = block.parentID
            let labels = block.labelIDs
            return { block.trashID = id; block.trashMetadataData = metadata; block.listID = list
                block.parentID = parent; block.labelIDs = labels }
        }
        let lists = affectedLists.map { list in
            let id = list.trashID, metadata = list.trashMetadataData, section = list.sectionID, pinned = list.isPinned, parent = list.parentListID
            return { list.trashID = id; list.trashMetadataData = metadata; list.sectionID = section; list.isPinned = pinned; list.parentListID = parent }
        }
        let taskIDs = Set(affected.map(\.id))
        let sessions = try context.fetch(FetchDescriptor<WorkSession>()).filter { taskIDs.contains($0.taskID) }.map { session in
            let end = session.endedAt, heartbeat = session.lastHeartbeatAt, reason = session.pauseReason
            return { session.endedAt = end; session.lastHeartbeatAt = heartbeat; session.pauseReason = reason }
        }
        restoreModels = { for restore in blocks + lists + sessions { restore() } }
    }

    func restore() { restoreModels() }
}
