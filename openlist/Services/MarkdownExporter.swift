//
//  MarkdownExporter.swift
//  openlist
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Renders a list document to Markdown and offers it as a file.
///
/// Superlist's own export lives behind integrations, but writing plain
/// Markdown needs nothing external, so the local app can do it outright.
enum MarkdownExporter {
    @MainActor
    static func markdown(for list: TaskList, store: Store) -> String {
        var output = "# \(list.icon) \(list.displayTitle)\n\n"
        if !list.summary.isEmpty {
            output += "\(list.summary)\n\n"
        }

        let blocks = store.blocks(inList: list.id)
        let rows = BlockTree.flatten(blocks, root: nil, respectCollapse: false)
        // Fetched once rather than per task row.
        let labelsByID = Dictionary(
            store.allLabels().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        output += render(rows: rows, labelsByID: labelsByID)
        return output
    }

    @MainActor
    private static func render(rows: [BlockRow], labelsByID: [UUID: TaskLabel]) -> String {
        var lines: [String] = []

        for row in rows {
            let block = row.block
            let indent = String(repeating: "  ", count: row.depth)

            switch block.kind {
            case .divider:
                lines.append("\(indent)---")

            case .image:
                let caption = block.mediaCaption.isEmpty ? "image" : block.mediaCaption
                let name = block.mediaFilename ?? ""
                lines.append("\(indent)![\(caption)](\(name))")

            case .heading1, .heading2, .heading3:
                let hashes = block.kind == .heading1 ? "##" : (block.kind == .heading2 ? "###" : "####")
                lines.append("\(indent)\(hashes) \(block.text)")

            case .task:
                var line = "\(indent)- [\(block.isCompleted ? "x" : " ")] \(block.text)"
                line += metadataSuffix(for: block, labelsByID: labelsByID)
                lines.append(line)

            case .bullet:
                lines.append("\(indent)- \(block.text)")

            case .numbered:
                lines.append("\(indent)\(max(1, row.ordinal)). \(block.text)")

            case .quote:
                lines.append("\(indent)> \(block.text)")

            case .code:
                lines.append("\(indent)```")
                lines.append("\(indent)\(block.text)")
                lines.append("\(indent)```")

            case .paragraph:
                lines.append("\(indent)\(block.text)")
            }

            if !block.note.isEmpty {
                for noteLine in block.note.components(separatedBy: .newlines) {
                    lines.append("\(indent)  > \(noteLine)")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func metadataSuffix(for block: Block, labelsByID: [UUID: TaskLabel]) -> String {
        var parts: [String] = []

        if let dueDate = block.dueDate {
            parts.append("📅 \(Store.absoluteDateText(dueDate, includesTime: block.includesTime))")
        }
        if let recurrence = block.recurrence {
            parts.append("🔁 \(recurrence.displayText)")
        }
        if block.isStarred {
            parts.append("⭐️")
        }
        parts.append(contentsOf: block.labelIDs.compactMap { labelsByID[$0] }.map { "#\($0.name)" })

        return parts.isEmpty ? "" : "  " + parts.joined(separator: " ")
    }

    // MARK: - Save panel

    @MainActor
    static func presentSavePanel(for list: TaskList, store: Store) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(list.displayTitle).md"
        panel.canCreateDirectories = true
        panel.title = "Export \(list.displayTitle)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = markdown(for: list, store: store)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copies the rendered Markdown to the pasteboard.
    @MainActor
    static func copyToPasteboard(list: TaskList, store: Store) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: list, store: store), forType: .string)
    }
}
