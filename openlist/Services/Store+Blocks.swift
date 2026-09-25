//
//  Store+Blocks.swift
//  openlist
//

import AppKit
import Foundation
import SwiftData

extension Store {
    // MARK: - Creating

    /// Inserts a new block directly after `reference` at the same depth.
    @discardableResult
    func insertBlock(
        kind: BlockKind = .paragraph,
        text: String = "",
        after reference: Block
    ) -> Block {
        let siblings = orderedSiblings(of: reference)
        let index = siblings.firstIndex { $0.id == reference.id } ?? siblings.count - 1
        let next = index + 1 < siblings.count ? siblings[index + 1].sortIndex : nil

        let block = Block(
            kind: kind,
            text: text,
            listID: resolvedListID(reference.listID),
            parentID: reference.parentID,
            sortIndex: BlockTree.index(after: reference.sortIndex, before: next)
        )
        context.insert(block)
        respaceIfNeeded(parentID: reference.parentID, listID: reference.listID)
        return block
    }

    /// Where a new child lands among its parent's existing children.
    enum ChildPosition {
        case first
        case last
    }

    /// Inserts a new block as a child of `parent`.
    @discardableResult
    func insertChild(
        kind: BlockKind = .task,
        text: String = "",
        of parent: Block,
        at position: ChildPosition = .first
    ) -> Block {
        let children = children(of: parent.id, listID: parent.listID ?? UUID())
        let sortIndex: Double = switch position {
        case .first:
            BlockTree.index(after: nil, before: children.first?.sortIndex)
        case .last:
            (children.last?.sortIndex ?? 0) + BlockTree.indexStep
        }

        let block = Block(
            kind: kind,
            text: text,
            listID: resolvedListID(parent.listID),
            parentID: parent.id,
            sortIndex: sortIndex
        )
        context.insert(block)
        return block
    }

    /// Appends a block to the end of a document, or of the subtree it is rooted at.
    @discardableResult
    func appendBlock(
        kind: BlockKind = .task,
        text: String = "",
        to document: DocumentContext
    ) -> Block {
        let listID = resolvedListID(document.listID) ?? document.listID
        let siblings = children(of: document.rootBlockID, listID: listID)
        let block = Block(
            kind: kind,
            text: text,
            listID: listID,
            parentID: document.rootBlockID,
            sortIndex: (siblings.last?.sortIndex ?? 0) + BlockTree.indexStep
        )
        context.insert(block)
        return block
    }

    /// Copies the complete subtree with independent media ownership.
    @discardableResult
    func duplicateBlock(_ block: Block) -> Block {
        do {
            let id = try copyBlock(block, mode: .duplicate)
            return self.block(id: id) ?? block
        } catch {
            actionError = "The \(block.isTask ? "task" : "item") was not duplicated because its content or a file could not be copied. \(error.localizedDescription)"
            return block
        }
    }

    // MARK: - Deleting

    /// Deletes a block. Its children are deleted too unless `liftChildren` is
    /// set, in which case they take the deleted block's place.
    func deleteBlock(_ block: Block, liftChildren: Bool = false) {
        guard let listID = block.listID else {
            discardTaskSchedule(for: block, reason: "Task deleted")
            context.delete(block)
            return
        }
        let all = blocks(inList: listID)

        if liftChildren {
            let kids = BlockTree.children(of: block.id, in: all)
            for (offset, child) in kids.enumerated() {
                child.parentID = block.parentID
                child.sortIndex = block.sortIndex + Double(offset + 1) * 0.001
            }
        } else {
            for descendant in BlockTree.descendants(of: block.id, in: all) {
                discardTaskSchedule(for: descendant, reason: "Task deleted")
                purgeMediaAndAttachments(for: descendant)
                context.delete(descendant)
            }
        }

        discardTaskSchedule(for: block, reason: "Task deleted")
        purgeMediaAndAttachments(for: block)
        let parentID = block.parentID
        context.delete(block)
        respaceIfNeeded(parentID: parentID, listID: listID)
    }

    // MARK: - Kind

    func changeKind(_ block: Block, to kind: BlockKind) {
        guard block.kind != kind else { return }
        let previous = block.kind
        block.kind = kind

        // Leaving task-hood drops scheduling metadata that no longer applies.
        if previous == .task, kind != .task {
            discardTaskSchedule(for: block, reason: "Changed to a note")
            block.occurrenceID = UUID()
            block.isCompleted = false
            block.completedAt = nil
            block.dueDate = nil
            block.reminderAt = nil
            block.recurrenceData = nil
            block.isStarred = false
            block.priorityRaw = 0
        }
        if kind.isVoid {
            block.text = ""
            block.richData = nil
        }
        block.touch()
    }

    /// Applies edited content, keeping the plain-text mirror in sync.
    func setContent(_ block: Block, attributed: NSAttributedString) {
        block.text = RichTextCodec.plainText(from: attributed)
        block.richData = RichTextCodec.encode(attributed, kind: block.kind)
        block.touch()
    }

    func setPlainText(_ block: Block, _ text: String) {
        block.text = text
        block.richData = nil
        block.touch()
    }

    /// Retitles a block from a plain-text field without discarding the inline
    /// styling the outline editor may have applied.
    func setText(_ text: String, for block: Block) {
        guard block.text != text else { return }
        // Inspector fields commit on Return/blur; this is a fallback if the
        // user pauses without leaving the field. Fast keystrokes coalesce.
        defer { scheduleSave(after: .seconds(1)) }
        guard block.richData != nil else {
            setPlainText(block, text)
            return
        }
        let updated = RichTextCodec.replacingText(in: attributedContent(of: block), with: text)
        setContent(block, attributed: updated)
    }

    // MARK: - Outdent

    /// Moves `block` out one level, becoming the next sibling of its parent.
    ///
    /// Siblings that followed `block` become its children, which is what keeps
    /// an outline stable when you promote a middle item.
    @discardableResult
    func outdent(_ block: Block) -> Bool {
        guard
            let parentID = block.parentID,
            let parent = self.block(id: parentID),
            let listID = block.listID
        else { return false }

        let all = blocks(inList: listID)
        let siblings = BlockTree.children(of: parentID, in: all)
        guard let index = siblings.firstIndex(where: { $0.id == block.id }) else { return false }

        let following = Array(siblings[(index + 1)...])
        let ownChildren = BlockTree.children(of: block.id, in: all)
        var nextIndex = (ownChildren.last?.sortIndex ?? 0) + BlockTree.indexStep
        for sibling in following {
            sibling.parentID = block.id
            sibling.sortIndex = nextIndex
            nextIndex += BlockTree.indexStep
        }

        let parentSiblings = BlockTree.children(of: parent.parentID, in: all)
        let parentPosition = parentSiblings.firstIndex { $0.id == parent.id } ?? 0
        let after = parentPosition + 1 < parentSiblings.count ? parentSiblings[parentPosition + 1].sortIndex : nil

        block.parentID = parent.parentID
        block.sortIndex = BlockTree.index(after: parent.sortIndex, before: after)
        block.touch()
        respaceIfNeeded(parentID: parent.parentID, listID: listID)
        return true
    }

    // MARK: - Moving

    /// Re-parents and repositions a block, refusing moves that would nest a
    /// block inside its own subtree.
    @discardableResult
    func move(_ block: Block, toParent parentID: UUID?, above target: Block?, in listID: UUID) -> Bool {
        let listID = resolvedListID(listID) ?? listID
        // The subtree still lives in the block's CURRENT list; reading the
        // destination would return nothing and silently orphan every child.
        let sourceListID = block.listID ?? listID
        let source = blocks(inList: sourceListID)
        let all = sourceListID == listID ? source : blocks(inList: listID)

        if let parentID {
            guard parentID != block.id,
                  !BlockTree.isDescendant(parentID, of: block.id, in: source)
            else { return false }
        }

        let siblings = BlockTree.children(of: parentID, in: all).filter { $0.id != block.id }
        block.listID = listID
        block.parentID = parentID

        if let target, let index = siblings.firstIndex(where: { $0.id == target.id }) {
            let previous = index > 0 ? siblings[index - 1].sortIndex : nil
            block.sortIndex = BlockTree.index(after: previous, before: siblings[index].sortIndex)
        } else {
            block.sortIndex = (siblings.last?.sortIndex ?? 0) + BlockTree.indexStep
        }

        // The subtree follows, so descendants need their list key updated too.
        for descendant in BlockTree.descendants(of: block.id, in: source) where descendant.listID != listID {
            descendant.listID = listID
            descendant.touch()
        }

        block.touch()
        respaceIfNeeded(parentID: parentID, listID: listID)
        return true
    }

    /// The attributed content for a block, decoded and styled for its kind.
    func attributedContent(of block: Block) -> NSAttributedString {
        RichTextCodec.decode(
            block.richData,
            plainText: block.text,
            kind: block.kind,
            isCompleted: block.isCompleted
        )
    }

    // MARK: - Collapse

    func toggleCollapse(_ block: Block) {
        setCollapsed(!block.isCollapsed, for: block)
    }

    func setCollapsed(_ collapsed: Bool, for block: Block) {
        guard block.isCollapsed != collapsed else { return }
        block.isCollapsed = collapsed
        block.touch()
        save()
    }

    // MARK: - Helpers

    func orderedSiblings(of block: Block) -> [Block] {
        guard let listID = block.listID else { return [block] }
        return BlockTree.children(of: block.parentID, in: blocks(inList: listID))
    }

    /// Rewrites sort indices when repeated midpoint inserts have exhausted the
    /// available precision between two neighbours.
    private func respaceIfNeeded(parentID: UUID?, listID: UUID?) {
        guard let listID else { return }
        let siblings = BlockTree.children(of: parentID, in: blocks(inList: listID))
        if BlockTree.needsRenormalisation(siblings) {
            BlockTree.renormalise(siblings)
        }
    }

    func purgeMediaAndAttachments(for block: Block) {
        if let filename = block.mediaFilename {
            removeEditorMedia(filename: filename)
        }
        for attachment in attachments(for: block.id) {
            removeEditorMedia(filename: attachment.filename)
            context.delete(attachment)
        }
    }
}
