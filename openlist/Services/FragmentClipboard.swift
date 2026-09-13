import AppKit

enum FragmentClipboard {
    static let type = NSPasteboard.PasteboardType("solimanali.openlist.document-fragment")
    static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")

    static func copy(_ ids: [UUID], store: Store, markdownOnly: Bool = false,
                     to pasteboard: NSPasteboard = .general) throws {
        let fragment = try FragmentContent.capture(ids, store: store, includingMedia: !markdownOnly)
        let data = markdownOnly ? nil : try fragment.encoded()
        let markdown = FragmentMarkdown.render(fragment, mediaAreEmbedded: !markdownOnly)
        let item = NSPasteboardItem()
        guard item.setString(markdown, forType: .string), item.setString(markdown, forType: markdownType),
              data.map({ item.setData($0, forType: type) }) ?? true else { throw FragmentError.clipboard }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw FragmentError.clipboard }
    }

    static func read(from pasteboard: NSPasteboard = .general) throws -> DocumentFragment {
        guard let data = pasteboard.data(forType: type) else {
            throw FragmentError.invalid("The clipboard has no Openlist content. Use ordinary Paste for text or Markdown.")
        }
        return try DocumentFragment.decode(data)
    }
}
