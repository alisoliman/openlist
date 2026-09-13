import Foundation

/// A presentation-only projection of local references in a plain task note.
/// Detection never rewrites the note or turns external text into commands.
nonisolated struct NoteItemLink: Identifiable, Equatable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }

    static func references(in text: String) -> [Self] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen: Set<String> = []
        let urls = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> URL? in
            guard let url = match.url, LocalLink.isLocal(url), seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
        return urls.enumerated().map { index, url in
            let parsed = try? LocalLink.parse(url, scheme: url.scheme?.lowercased() ?? "")
            let kind: String
            switch parsed?.target {
            case .task: kind = "task"
            case .list: kind = "list"
            case nil: kind = "Openlist"
            }
            let number = urls.count > 1 ? " \(index + 1)" : ""
            return Self(url: url, title: "Open \(kind) link\(number)")
        }
    }
}
