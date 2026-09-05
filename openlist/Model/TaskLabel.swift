//
//  TaskLabel.swift
//  openlist
//

import Foundation
import SwiftData

/// A tag that can be attached to any task, created inline by typing `#`.
///
/// Named `TaskLabel` rather than `Label` so it never shadows SwiftUI's view.
@Model
final class TaskLabel {
    var id: UUID = UUID()
    var name: String = ""
    var accentRaw: String = ListAccent.violet.rawValue
    var sortIndex: Double = 0
    var createdAt: Date = Date.now

    init(name: String, accent: ListAccent = .violet, sortIndex: Double = 0) {
        self.id = UUID()
        self.name = name
        self.accentRaw = accent.rawValue
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}

extension TaskLabel {
    var accent: ListAccent {
        get { ListAccent(rawValue: accentRaw) ?? .violet }
        set { accentRaw = newValue.rawValue }
    }

    /// Names are stored without the leading `#` and matched case-insensitively.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("#") { value.removeFirst() }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A stable accent chosen from the label's name, so a freshly typed `#tag`
    /// gets a consistent colour without asking the user.
    static func suggestedAccent(for name: String) -> ListAccent {
        let palette: [ListAccent] = [.violet, .blue, .green, .orange, .pink, .teal, .indigo, .amber, .red, .brown]
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }
}
