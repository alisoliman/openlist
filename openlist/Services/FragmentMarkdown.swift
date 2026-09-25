import Foundation

enum FragmentMarkdown {
    /// Portable textual fallback deliberately describes files instead of
    /// publishing private, short-lived local cache paths as broken links.
    static func render(_ fragment: DocumentFragment) -> String {
        let byID = Dictionary(uniqueKeysWithValues: fragment.blocks.map { ($0.id, $0) })
        let labels = Dictionary(uniqueKeysWithValues: fragment.labels.map { ($0.id, $0.name) })
        let children = Dictionary(grouping: fragment.blocks, by: \.parentID)
        var stack = fragment.roots.reversed().map { ($0, 0) }
        var lines: [String] = []
        while let (id, depth) = stack.popLast(), let block = byID[id] {
            let indent = String(repeating: "  ", count: depth)
            let text = InlineMarkdown.string(from: FragmentContent.attributedText(block))
            switch block.kind {
            case "task":
                let tags = block.labelIDs.compactMap { labels[$0] }.map { " #" + InlineMarkdown.escape($0) }.joined()
                lines.append("\(indent)- [\(block.isCompleted ? "x" : " ")] \(text)\(block.isStarred ? " ⭐" : "")\(tags)")
            case "heading1": lines.append(indent + "# " + text)
            case "heading2": lines.append(indent + "## " + text)
            case "heading3": lines.append(indent + "### " + text)
            case "bullet": lines.append(indent + "- " + text)
            case "numbered": lines.append(indent + "1. " + text)
            case "quote": lines += text.components(separatedBy: .newlines).map { indent + "> " + $0 }
            case "code":
                let fence = InlineMarkdown.codeFence(for: block.text)
                lines.append(indent + fence)
                lines += block.text.components(separatedBy: .newlines).map { indent + $0 }
                lines.append(indent + fence)
            case "divider": lines.append(indent + "---")
            case "image": lines.append(indent + InlineMarkdown.escape(block.mediaCaption.isEmpty ? "Image" : block.mediaCaption)
                + " (image included in Openlist content)")
            default: lines.append(indent + text)
            }
            if !block.note.isEmpty {
                lines += block.note.components(separatedBy: .newlines).map { indent + "  > " + InlineMarkdown.escape($0) }
            }
            for file in block.attachments {
                lines.append(indent + "  Attachment: " + InlineMarkdown.escape(file.displayName)
                    + " (file included in Openlist content)")
            }
            stack += (children[id] ?? []).reversed().map { ($0.id, depth + 1) }
        }
        return lines.joined(separator: "\n")
    }
}
