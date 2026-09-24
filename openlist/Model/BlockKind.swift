//
//  BlockKind.swift
//  openlist
//

import Foundation

/// The type of a block inside a list document.
///
/// Superlist treats a list as a rich document: it can hold tasks, paragraphs,
/// headings, bullets, numbered items, quotes, code, dividers and images all in
/// the same vertical flow, at any nesting depth.
enum BlockKind: String, Codable, CaseIterable, Sendable {
    case task
    case paragraph
    case heading1
    case heading2
    case heading3
    case bullet
    case numbered
    case quote
    case code
    case divider
    case image

    var title: String {
        switch self {
        case .task: "Task"
        case .paragraph: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bullet: "Bullet list"
        case .numbered: "Numbered list"
        case .quote: "Quote"
        case .code: "Code"
        case .divider: "Divider"
        case .image: "Image"
        }
    }

    var subtitle: String {
        switch self {
        case .task: "Something to get done"
        case .paragraph: "Plain text"
        case .heading1: "Big section heading"
        case .heading2: "Medium section heading"
        case .heading3: "Small section heading"
        case .bullet: "An unordered list"
        case .numbered: "An ordered list"
        case .quote: "Call out a quotation"
        case .code: "Monospaced snippet"
        case .divider: "Visually split content"
        case .image: "Embed a picture"
        }
    }

    var symbol: String {
        switch self {
        case .task: "checkmark.square"
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        case .image: "photo"
        }
    }

    /// Blocks that can never hold text.
    var isVoid: Bool { self == .divider || self == .image }

    /// Blocks the user can nest children under.
    var acceptsChildren: Bool { !isVoid }

    /// Keywords used to filter this kind inside the slash menu.
    var searchTerms: [String] {
        switch self {
        case .task: ["task", "todo", "check", "checkbox"]
        case .paragraph: ["text", "paragraph", "plain", "body"]
        case .heading1: ["heading", "h1", "title", "large"]
        case .heading2: ["heading", "h2", "subtitle", "medium"]
        case .heading3: ["heading", "h3", "small"]
        case .bullet: ["bullet", "list", "unordered", "ul"]
        case .numbered: ["number", "ordered", "list", "ol"]
        case .quote: ["quote", "blockquote", "cite"]
        case .code: ["code", "snippet", "mono"]
        case .divider: ["divider", "separator", "rule", "line", "hr"]
        case .image: ["image", "picture", "photo", "media"]
        }
    }
}
