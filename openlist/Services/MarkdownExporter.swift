#if os(macOS)
import AppKit
#endif
import Foundation

/// Renders list documents with stored formatting and portable media references.
enum MarkdownExporter {
    @MainActor
    static func markdown(for list: TaskList, store: Store) throws -> String {
        let hierarchy = store.listHierarchy()
        let documents = hierarchy.subtree(of: list.id)
        let paths = Dictionary(try documents.flatMap { try assets(for: $0, store: store) }
            .map { ($0.key, $0.source.absoluteString) }, uniquingKeysWith: { first, _ in first })
        if documents.count == 1 { return render(list: list, store: store) { paths[$0] ?? $0 } }
        return documents.map { document in
            "Document: \(InlineMarkdown.escape(hierarchy.path(for: document.id)))\n\n"
                + render(list: document, store: store) { paths[$0] ?? $0 }
        }.joined(separator: "\n---\n\n")
    }

    @MainActor
    static func write(list: TaskList, store: Store, to destination: URL) throws {
        try prepare(list: list, store: store, to: destination).publish()
    }

    /// The list's export, gathered on the main actor: the files it copies
    /// and its Markdown, written with a placeholder for each file's link,
    /// which `Prepared.publish` fills in once it knows where the file went.
    /// A list with nested lists is a folder of linked documents.
    @MainActor
    static func prepare(list: TaskList, store: Store, to destination: URL) throws -> Prepared {
        let hierarchy = store.listHierarchy()
        let documents = hierarchy.subtree(of: list.id)
        if documents.count <= 1 {
            let assets = try assets(for: list, store: store)
            let placeholders = Prepared.placeholders(for: assets)
            return Prepared(destination: destination, assets: assets, placeholders: placeholders,
                            document: render(list: list, store: store) { placeholders[$0] ?? $0 }, documents: [:])
        }
        let names = Dictionary(uniqueKeysWithValues: documents.map {
            ($0.id, MarkdownExportPackage.safeFilename($0.displayTitle) + "-" + $0.id.uuidString + ".md")
        })
        let assets = try documents.flatMap { try assets(for: $0, store: store) }
        let placeholders = Prepared.placeholders(for: assets)
        let markdown = Dictionary(uniqueKeysWithValues: documents.map { document in
            var navigation = ""
            if let parent = hierarchy.parent(of: document.id), let filename = names[parent.id] {
                navigation += "Parent: [\(InlineMarkdown.escape(parent.displayTitle))](\(InlineMarkdown.destination(filename)))\n\n"
            }
            let children = hierarchy.children(of: document.id).filter { names[$0.id] != nil }
            if !children.isEmpty {
                navigation += "Child lists:\n" + children.map {
                    "- [\(InlineMarkdown.escape($0.displayTitle))](\(InlineMarkdown.destination(names[$0.id]!)))"
                }.joined(separator: "\n") + "\n\n"
            }
            return (names[document.id]!, navigation + render(list: document, store: store) { placeholders[$0] ?? $0 })
        })
        return Prepared(destination: destination, assets: assets, placeholders: placeholders, document: nil, documents: markdown)
    }

    /// A list's export ready to write anywhere, the main actor included:
    /// where it goes, the files it copies, and its Markdown, one document or
    /// a folder of them by file name.
    nonisolated struct Prepared: Sendable {
        let destination: URL
        let assets: [MarkdownExportPackage.Asset]
        /// What stands for each file's link in the Markdown, by its asset key.
        let placeholders: [String: String]
        /// The one document, or nil for a folder of `documents`.
        let document: String?
        let documents: [String: String]

        /// How many files it copies, which `publish` counts.
        var fileCount: Int { placeholders.count }

        /// Copies the files and writes the Markdown. `copied` hears how many
        /// files are in after each; throwing from it stops the export, with
        /// nothing left behind.
        func publish(copied: (Int) throws -> Void = { _ in }) throws {
            if let document {
                try MarkdownExportPackage.write(to: destination, assets: assets, render: { fill(document, $0) }, copied: copied)
            } else {
                try MarkdownExportPackage.writeFolder(to: destination, assets: assets,
                    render: { paths in documents.mapValues { fill($0, paths) } }, copied: copied)
            }
        }

        /// `markdown` with each file's placeholder turned into a link to where it went.
        private func fill(_ markdown: String, _ paths: [String: String]) -> String {
            placeholders.reduce(markdown) { text, file in
                text.replacingOccurrences(of: InlineMarkdown.destination(file.value),
                                          with: InlineMarkdown.destination(paths[file.key] ?? file.key))
            }
        }

        /// A placeholder for each file, unique to this export, so no text
        /// written in a list can be mistaken for one.
        fileprivate static func placeholders(for assets: [MarkdownExportPackage.Asset]) -> [String: String] {
            Dictionary(assets.map { ($0.key, "openlist-export-file-" + UUID().uuidString) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// The lists Settings' Export every list writes: each top-level list,
    /// with how many lists its own Export writes, itself and those nested in
    /// it, so a list with nested lists is one folder holding them all and
    /// none is written twice.
    @MainActor
    static func everyList(store: Store) -> [(list: TaskList, documents: Int)] {
        let hierarchy = store.listHierarchy()
        return store.allLists(includeArchived: true).filter { hierarchy.parent(of: $0.id) == nil }
            .map { ($0, hierarchy.subtree(of: $0.id).count) }
    }

    /// Settings' Export every list, at once: each of `everyList` in `folder`,
    /// as its own Export writes it. `wrote` hears how many lists each write
    /// took, so a failure part way can say how many were exported.
    @MainActor
    static func writeAll(store: Store, to folder: URL, wrote: (Int) -> Void = { _ in }) throws {
        for (list, documents) in everyList(store: store) {
            try write(list: list, store: store, to: destination(for: list, in: folder, documents: documents))
            wrote(documents)
        }
    }

    /// Where a list's export goes in `folder`: "List.md", or a "List" folder
    /// when it has nested lists, a new name beside what's there.
    @MainActor
    static func destination(for list: TaskList, in folder: URL, documents: Int) -> URL {
        let name = MarkdownExportPackage.safeFilename(list.displayTitle)
        return MarkdownExportPackage.availableURL(in: folder, filename: documents > 1 ? name : name + ".md")
    }

    @MainActor
    private static func assets(for list: TaskList, store: Store) throws -> [MarkdownExportPackage.Asset] {
        var assets: [MarkdownExportPackage.Asset] = []
        if let cover = try list.validatedCover() {
            assets.append(.init(key: cover.filename,
                source: try MediaStore.shared.materialize(filename: cover.filename, data: list.coverData),
                preferredFilename: cover.metadata.displayName))
        }
        for block in store.blocks(inList: list.id) {
            if let filename = block.mediaFilename {
                assets.append(.init(
                    key: filename,
                    source: try MediaStore.shared.materialize(filename: filename, data: block.mediaData),
                    preferredFilename: filename
                ))
            }
            for attachment in store.attachments(for: block.id) {
                assets.append(.init(
                    key: attachment.filename,
                    source: try attachment.fileURL(),
                    preferredFilename: attachment.displayName.isEmpty ? attachment.filename : attachment.displayName
                ))
            }
        }
        return assets
    }

    @MainActor
    private static func render(list: TaskList, store: Store, mediaPath: (String) -> String) -> String {
        // The glyph the app draws; an SF Symbol's name from synced or older
        // data, which Markdown can't draw, is left out rather than written.
        let glyph = ListIcon.isSymbolName(list.glyph) ? "" : InlineMarkdown.escape(list.glyph) + " "
        var output = "# \(glyph)\(InlineMarkdown.escape(list.displayTitle))\n\n"
        if let filename = list.coverFilename {
            output += "![\(InlineMarkdown.escape(list.displayTitle + " cover"))](\(InlineMarkdown.destination(mediaPath(filename))))\n\n"
        }
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

    #if os(macOS)
    // MARK: - Clipboard

    /// Puts the list's document on the clipboard as the Markdown Export
    /// writes for it. `false`, after saying why in the window's notice, when
    /// it couldn't.
    @MainActor
    @discardableResult
    static func copyToPasteboard(list: TaskList, store: Store) -> Bool {
        do {
            let content = try markdown(for: list, store: store)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            return true
        } catch {
            store.actionError = "“\(list.displayTitle)” could not be copied as Markdown. \(error.localizedDescription)"
            return false
        }
    }
    #endif
}
