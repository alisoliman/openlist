import Foundation
import SwiftData

/// Only local title edits can authorize inline metadata parsing. Merely opening
/// a stored, copied or restored row must preserve its literal title and fields.
struct InlineMetadataEdits {
    private struct Edit {
        let block: Block
        let originalText: String
        let editedText: String
    }
    private var edits: [UUID: Edit] = [:]

    mutating func recordTextChange(for block: Block, to text: String) {
        guard block.modelContext != nil, !block.isDeleted, block.text != text else { return }
        let original: String
        if let previous = edits[block.id], previous.block === block, previous.editedText == block.text {
            original = previous.originalText
        } else {
            original = block.text
        }
        if text == original {
            edits.removeValue(forKey: block.id)
        } else {
            edits[block.id] = Edit(block: block, originalText: original, editedText: text)
        }
    }

    mutating func consume(for block: Block) -> Bool {
        guard block.modelContext != nil, !block.isDeleted,
              let edit = edits.removeValue(forKey: block.id) else { return false }
        // Structural Redo can reuse a UUID with a new model instance. External
        // text changes also supersede a pending local edit without being parsed.
        return edit.block === block && edit.editedText == block.text
    }

    mutating func retain(blockIDs: Set<UUID>) {
        edits = edits.filter { blockIDs.contains($0.key) }
    }
}
