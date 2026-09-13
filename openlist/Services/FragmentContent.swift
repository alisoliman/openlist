import AppKit
import SwiftData

enum FragmentContent {
    static func capture(_ selection: [UUID], store: Store, includingMedia: Bool = true) throws -> DocumentFragment {
        guard !selection.isEmpty, let first = store.block(id: selection[0]), let listID = first.listID else {
            throw CopyError.unavailable
        }
        let all = try store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.listID == listID }))
            .filter { !$0.isDeleted }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(selection)
        guard selected.isSubset(of: Set(byID.keys)), all.allSatisfy({ $0.sortIndex.isFinite }) else {
            throw CopyError.unavailable
        }
        var roots = selected
        for id in selected {
            var visited: Set<UUID> = [id]
            var parent = byID[id]?.parentID
            while let ancestor = parent {
                guard visited.insert(ancestor).inserted, let block = byID[ancestor] else {
                    throw FragmentError.invalid("The source has an incomplete or cyclic outline.")
                }
                if selected.contains(ancestor) { roots.remove(id) }
                parent = block.parentID
            }
        }
        func path(to id: UUID) -> [Block] {
            var path: [Block] = []
            var current = byID[id]
            while let block = current {
                path.append(block)
                current = block.parentID.flatMap { byID[$0] }
            }
            return path.reversed()
        }
        let paths = Dictionary(uniqueKeysWithValues: roots.map { ($0, path(to: $0)) })
        let orderedRoots = roots.sorted { left, right in
            let lhs = paths[left]!, rhs = paths[right]!
            for (a, b) in zip(lhs, rhs) where a.id != b.id {
                return a.sortIndex == b.sortIndex ? a.id.uuidString < b.id.uuidString : a.sortIndex < b.sortIndex
            }
            return lhs.count < rhs.count
        }
        let children = Dictionary(grouping: all, by: \.parentID).mapValues {
            $0.sorted { $0.sortIndex == $1.sortIndex ? $0.id.uuidString < $1.id.uuidString : $0.sortIndex < $1.sortIndex }
        }
        var originals: [Block] = []
        var stack = orderedRoots.reversed().compactMap { byID[$0] }
        var seen = Set<UUID>()
        while let block = stack.popLast() {
            guard seen.insert(block.id).inserted, seen.count <= 10_000 else {
                throw FragmentError.invalid("The source is cyclic or contains more than 10,000 blocks.")
            }
            originals.append(block)
            stack += (children[block.id] ?? []).reversed()
        }
        let labels = try store.context.fetch(FetchDescriptor<TaskLabel>()).filter { !$0.isDeleted }
        let wantedLabels = Set(originals.flatMap(\.labelIDs))
        let availableLabels = labels.filter { wantedLabels.contains($0.id) }
        guard Set(availableLabels.map(\.id)) == wantedLabels else {
            throw FragmentError.invalid("A source label is unavailable. Let the library finish syncing and try again.")
        }
        var totalMediaBytes = 0
        func readMedia(filename: String, data: Data?) throws -> FragmentMedia {
            let asset = try media(filename: filename, data: data)
            totalMediaBytes += asset.data.count
            guard totalMediaBytes <= DocumentFragment.maximumMediaBytes else { throw FragmentError.tooLarge }
            return asset
        }
        let records = try originals.map { block in
            var record = FragmentBlock(id: block.id, parentID: roots.contains(block.id) ? nil : block.parentID,
                kind: block.kindRaw, text: block.text)
            let content = NSMutableAttributedString(attributedString:
                RichTextCodec.decode(block.richData, plainText: block.text, kind: .paragraph))
            // The editor's plain-text mirror omits attachment placeholders.
            // Removing them through attributed mutations also shifts the
            // following supported style ranges into that canonical text.
            while let range = content.string.range(of: "\u{fffc}", options: .backwards) {
                content.deleteCharacters(in: NSRange(range, in: content.string))
            }
            record.styles = styles(from: content)
            record.isCollapsed = block.isCollapsed
            record.isCompleted = block.isCompleted
            record.completedAt = block.completedAt
            record.dueDate = block.dueDate
            record.includesTime = block.includesTime
            record.reminderAt = block.reminderAt
            record.recurrence = block.recurrence
            if block.recurrenceData != nil, record.recurrence == nil {
                throw FragmentError.invalid("A source repeat rule cannot be read.")
            }
            record.recurrence?.completedOccurrences = 0
            record.selectedForDay = block.selectedForDay
            record.deferredUntil = block.deferredUntil
            record.isStarred = block.isStarred
            record.priority = block.priorityRaw
            record.labelIDs = Array(Set(block.labelIDs)).sorted { $0.uuidString < $1.uuidString }
            record.note = block.note
            record.schedulingEstimateMinutes = block.schedulingEstimateMinutes
            record.keepsSessionsTogether = block.keepsSessionsTogether
            record.tracksAwayFromMac = block.tracksAwayFromMac
            if includingMedia {
                if let filename = block.mediaFilename {
                    record.image = try readMedia(filename: filename, data: block.mediaData)
                } else if block.mediaData != nil {
                    throw FragmentError.invalid("A source image has no filename.")
                }
            }
            record.mediaWidth = block.mediaWidth
            record.mediaHeight = block.mediaHeight
            record.mediaCaption = block.mediaCaption
            let blockID = block.id
            record.attachments = try store.context.fetch(FetchDescriptor<Attachment>(
                predicate: #Predicate { $0.blockID == blockID },
                sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))
                .filter { !$0.isDeleted }.map {
                    FragmentAttachment(displayName: $0.displayName, contentType: $0.contentType,
                        media: includingMedia ? try readMedia(filename: $0.filename, data: $0.contentData)
                            : FragmentMedia(fileExtension: "", data: Data()))
                }
            return record
        }
        let value = DocumentFragment(roots: orderedRoots, blocks: records,
            labels: availableLabels.map { FragmentLabel(id: $0.id, name: $0.name, accent: $0.accentRaw) })
        try value.validate()
        return value
    }

    private static func media(filename: String, data: Data?) throws -> FragmentMedia {
        guard !filename.isEmpty, filename != ".", filename != "..", (filename as NSString).lastPathComponent == filename else {
            throw FragmentError.invalid("A source file has an invalid path.")
        }
        let size = try data?.count ?? (FileManager.default.attributesOfItem(atPath: MediaStore.shared.url(for: filename).path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= DocumentFragment.maximumAssetBytes else { throw FragmentError.tooLarge }
        let value = FragmentMedia(fileExtension: (filename as NSString).pathExtension,
            data: try data ?? MediaStore.shared.readFile(filename: filename))
        try value.validate()
        return value
    }

    static func styles(from text: NSAttributedString) -> [FragmentTextStyle] {
        var result: [FragmentTextStyle] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            let style = FragmentTextStyle(location: range.location, length: range.length,
                bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask),
                strikethrough: (attributes[.openlistStrikethrough] as? Bool) == true,
                code: (attributes[.openlistInlineCode] as? Bool) == true, link: link)
            if style.bold || style.italic || style.strikethrough || style.code || style.link != nil { result.append(style) }
        }
        return result
    }

    static func attributedText(_ block: FragmentBlock) -> NSAttributedString {
        let text = NSMutableAttributedString(string: block.text, attributes: RichTextCodec.baseAttributes(for: .paragraph))
        for style in block.styles {
            let range = NSRange(location: style.location, length: style.length)
            var font = style.code ? NSFont.monospacedSystemFont(ofSize: Theme.Editor.codePointSize, weight: .regular)
                : Theme.Editor.nsFont(for: .paragraph)
            if style.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if style.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            text.addAttribute(.font, value: font, range: range)
            if style.code { text.addAttribute(.openlistInlineCode, value: true, range: range) }
            if style.strikethrough {
                text.addAttribute(.openlistStrikethrough, value: true, range: range)
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if let link = style.link { text.addAttribute(.link, value: link, range: range) }
        }
        return text
    }
}
