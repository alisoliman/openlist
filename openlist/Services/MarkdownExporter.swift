import AppKit
import Foundation
import UniformTypeIdentifiers

/// Renders list documents with stored formatting and portable media references.
enum MarkdownExporter {
    @MainActor
    static func markdown(for list: TaskList, store: Store) -> String {
        // Clipboard export cannot bundle files, so its media links point to the
        // actual local files instead of unusable relative storage filenames.
        render(list: list, store: store) { MediaStore.shared.url(for: $0).absoluteString }
    }

    @MainActor
    static func write(list: TaskList, store: Store, to destination: URL) throws {
        var assets: [MarkdownExportPackage.Asset] = []
        for block in store.blocks(inList: list.id) {
            if let filename = block.mediaFilename {
                assets.append(.init(key: filename, source: MediaStore.shared.url(for: filename), preferredFilename: filename))
            }
            for attachment in store.attachments(for: block.id) {
                assets.append(.init(
                    key: attachment.filename,
                    source: attachment.url,
                    preferredFilename: attachment.displayName.isEmpty ? attachment.filename : attachment.displayName
                ))
            }
        }
        try MarkdownExportPackage.write(to: destination, assets: assets) { paths in
            render(list: list, store: store) { paths[$0] ?? $0 }
        }
    }

    @MainActor
    private static func render(list: TaskList, store: Store, mediaPath: (String) -> String) -> String {
        var output = "# \(InlineMarkdown.escape(list.icon)) \(InlineMarkdown.escape(list.displayTitle))\n\n"
        if !list.summary.isEmpty { output += InlineMarkdown.escape(list.summary) + "\n\n" }

        let rows = BlockTree.flatten(store.blocks(inList: list.id), root: nil, respectCollapse: false)
        let labelsByID = Dictionary(store.allLabels().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        var previousKind: BlockKind?
        for row in rows {
            let block = row.block
            let indent = String(repeating: "  ", count: row.depth)
            // Decode as body text so the block's presentation (heading weight,
            // completion strike) is not mistaken for user-applied formatting.
            let attributed = RichTextCodec.decode(block.richData, plainText: block.text, kind: .paragraph)
            let text = InlineMarkdown.string(from: attributed)
            let isListItem = [.task, .bullet, .numbered].contains(block.kind)
            let previousWasListItem = previousKind.map { [.task, .bullet, .numbered].contains($0) } ?? false
            if !lines.isEmpty, !(isListItem && previousWasListItem) { lines.append("") }

            switch block.kind {
            case .divider:
                lines.append("\(indent)---")
            case .image:
                let caption = InlineMarkdown.escape(block.mediaCaption.isEmpty ? "image" : block.mediaCaption)
                if let filename = block.mediaFilename {
                    lines.append("\(indent)![\(caption)](\(InlineMarkdown.destination(mediaPath(filename))))")
                } else {
                    lines.append("\(indent)\(caption) (image unavailable)")
                }
            case .heading1, .heading2, .heading3:
                let hashes = block.kind == .heading1 ? "##" : (block.kind == .heading2 ? "###" : "####")
                lines.append("\(indent)\(hashes) \(text)")
            case .task:
                lines.append("\(indent)- [\(block.isCompleted ? "x" : " ")] \(text)\(metadataSuffix(for: block, labelsByID: labelsByID))")
            case .bullet:
                lines.append("\(indent)- \(text)")
            case .numbered:
                lines.append("\(indent)\(max(1, row.ordinal)). \(text)")
            case .quote:
                lines.append(contentsOf: text.components(separatedBy: .newlines).map { "\(indent)> \($0)" })
            case .code:
                let fence = InlineMarkdown.codeFence(for: block.text)
                lines.append(indent + fence)
                lines.append(contentsOf: block.text.components(separatedBy: .newlines).map { indent + $0 })
                lines.append(indent + fence)
            case .paragraph:
                lines.append(indent + text)
            }

            if !block.note.isEmpty {
                lines.append("")
                let noteIndent = isListItem ? indent + "  " : indent
                lines.append(contentsOf: block.note.components(separatedBy: .newlines).map { "\(noteIndent)> \(InlineMarkdown.escape($0))" })
            }
            for attachment in store.attachments(for: block.id) {
                let name = InlineMarkdown.escape(attachment.displayName.isEmpty ? "Attachment" : attachment.displayName)
                let attachmentIndent = isListItem ? indent + "  " : indent
                lines.append("")
                lines.append("\(attachmentIndent)[📎 \(name)](\(InlineMarkdown.destination(mediaPath(attachment.filename))))")
            }
            previousKind = block.kind
        }
        output += lines.joined(separator: "\n") + "\n"
        return output
    }

    @MainActor
    private static func metadataSuffix(for block: Block, labelsByID: [UUID: TaskLabel]) -> String {
        var parts: [String] = []
        if let dueDate = block.dueDate {
            parts.append("📅 \(Store.absoluteDateText(dueDate, includesTime: block.includesTime))")
        }
        if let recurrence = block.recurrence { parts.append("🔁 \(recurrence.displayText)") }
        if block.isStarred { parts.append("⭐️") }
        if block.priority != .none { parts.append("Priority: \(block.priority.title)") }
        parts.append(contentsOf: block.labelIDs.compactMap { labelsByID[$0] }.map { "#\($0.name)" })
        return parts.isEmpty ? "" : "  " + parts.map(InlineMarkdown.escape).joined(separator: " ")
    }

    // MARK: - Save panel

    @MainActor
    static func presentSavePanel(for list: TaskList, store: Store) {
        let blocks = store.blocks(inList: list.id)
        let hasMedia = blocks.contains { $0.mediaFilename != nil || !store.attachments(for: $0.id).isEmpty }
        let filename = "\(MarkdownExportPackage.safeFilename(list.displayTitle)).md"
        let url: URL
        if hasMedia {
            // A save-panel grant covers the selected file, not an arbitrary
            // sibling assets folder. Select its parent to grant the sandbox
            // access to both parts of this portable export.
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.title = "Export \(list.displayTitle)"
            panel.prompt = "Export"
            panel.message = "Choose a folder for \(filename) and its images and attachments. Keep the Markdown file and assets folder together when sharing. Existing files are kept."
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            url = MarkdownExportPackage.availableURL(in: folder, filename: filename)
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            panel.title = "Export \(list.displayTitle)"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            url = destination
        }
        do {
            try write(list: list, store: store, to: url)
        } catch {
            presentError(error, operation: "Export list")
        }
    }

    @MainActor
    static func presentError(_ error: Error, operation: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(operation) failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    static func copyToPasteboard(list: TaskList, store: Store) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: list, store: store), forType: .string)
    }
}
