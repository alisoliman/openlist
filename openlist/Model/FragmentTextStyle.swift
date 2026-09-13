import Foundation

/// Only the editor's supported text attributes cross the clipboard. No RTF,
/// object archives, HTML, or remote attachment loaders are decoded on paste.
nonisolated struct FragmentTextStyle: Codable, Equatable, Sendable {
    var location: Int
    var length: Int
    var bold = false
    var italic = false
    var strikethrough = false
    var code = false
    var link: String?
}
