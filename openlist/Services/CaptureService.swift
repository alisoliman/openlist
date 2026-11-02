//
//  CaptureService.swift
//  openlist
//

import AppKit

/// Services ▸ Add to Openlist, from any app's selection or a link's menu:
/// Quick Add opens with the words, and a link's address as the note, to
/// edit, aim and add. Nothing is saved until Return, as with anything else
/// Quick Add takes.
@MainActor
final class CaptureService: NSObject {
    static let shared = CaptureService()

    /// The message the Info.plist's NSServices names.
    @objc func addTask(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let shared = Self.shared(from: pasteboard) else {
            error.pointee = "There’s nothing to add." as NSString
            return
        }
        QuickCapturePanel.shared.show(QuickCaptureRequest(text: shared.text, note: shared.note))
    }

    /// What a pasteboard shares: its words, and a web link's address as a
    /// note. A link alone, or an address copied as text, is the note, the
    /// title left to type; a link's own text, when it has some, is the title.
    nonisolated static func shared(from pasteboard: NSPasteboard) -> (text: String, note: String?)? {
        let link = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { !$0.isFileURL }
        let words = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let link {
            return (words == link.absoluteString ? "" : words, link.absoluteString)
        }
        guard !words.isEmpty else { return nil }
        if let address = URL(string: words), ["http", "https"].contains(address.scheme?.lowercased() ?? ""),
           !words.contains(where: \.isWhitespace) {
            return ("", words)
        }
        return (words, nil)
    }
}
