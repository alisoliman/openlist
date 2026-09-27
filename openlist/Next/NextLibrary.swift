//
//  NextLibrary.swift
//  openlist
//

import SwiftUI

// The library view itself, `NextLibrary`, and its queries are UI-free and
// shared with the phone (NextLibraryCore.swift); this file holds the Mac's
// colours, environment and glyph views over it.

extension TaskList {
    @MainActor var nxColor: Color { isSystemInbox ? NX.inbox : accent.color }
}

extension TaskLabel {
    @MainActor var nxColor: Color { accent.color }
}

private struct NextLibraryKey: EnvironmentKey {
    static let defaultValue = NextLibrary()
}

extension EnvironmentValues {
    var nextLibrary: NextLibrary {
        get { self[NextLibraryKey.self] }
        set { self[NextLibraryKey.self] = newValue }
    }
}

/// Glyph for list icons that may be an emoji or an SF Symbol name.
struct NXListGlyph: View {
    let list: TaskList
    var size: CGFloat = 14

    /// Whether a list icon names an SF Symbol rather than being an emoji,
    /// by the rule the widgets share (`ListIcon`).
    static func isSymbolName(_ icon: String) -> Bool { ListIcon.isSymbolName(icon) }

    var body: some View {
        let icon = list.glyph
        if Self.isSymbolName(icon) {
            Image(systemName: icon)
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundStyle(list.nxColor)
        } else {
            Text(icon).font(.system(size: Self.emojiPointSize(size)))
        }
    }

    /// The emoji's size for a design size, which the widget shares (`EmojiSize`).
    static func emojiPointSize(_ size: CGFloat) -> CGFloat { EmojiSize.points(forDesign: size) }

    /// A list icon to run inline with text at `size`, as the design's
    /// `emoji + " " + name` strings: the emoji at the design's size rather
    /// than Core Text's larger one, or the SF Symbol, in `color` if given.
    static func text(_ icon: String, size: CGFloat, color: Color? = nil) -> Text {
        guard isSymbolName(icon) else { return Text(verbatim: icon).font(.system(size: emojiPointSize(size))) }
        let symbol = Text(Image(systemName: icon)).font(.system(size: size * 0.9, weight: .medium))
        return color.map { symbol.foregroundStyle($0) } ?? symbol
    }

    /// A list's glyph inline with text at `size`, a symbol in the list's colour.
    static func text(_ list: TaskList, size: CGFloat) -> Text {
        text(list.glyph, size: size, color: list.nxColor)
    }
}

/// A list as a menu item, as in Move to: its emoji before its name, or its
/// symbol as the item's image rather than the symbol's name as text.
struct NXListMenuButton: View {
    let list: TaskList
    let action: () -> Void

    var body: some View {
        let icon = list.glyph
        if NXListGlyph.isSymbolName(icon) {
            Button(list.displayTitle, systemImage: icon, action: action)
        } else {
            Button("\(icon) \(list.displayTitle)", action: action)
        }
    }
}

// MARK: - Workbench queries

extension NextLibrary {
    /// Inbox tasks waiting for a decision, oldest first, without those the
    /// window's triage kept for later or is still closing.
    @MainActor
    func inboxQueue(_ workbench: Workbench) -> [Block] {
        inboxQueue(kept: workbench.kept, closing: Set(workbench.closing.keys))
    }

    @MainActor
    func keptInbox(_ workbench: Workbench) -> [Block] {
        keptInbox(kept: workbench.kept)
    }

    /// Open work that belongs on Today: due or overdue, planned, or starred.
    @MainActor
    func isToday(_ task: Block, _ workbench: Workbench) -> Bool {
        guard !task.isCompleted || workbench.closing[task.id] != nil else { return false }
        if task.isDueOnOrBeforeToday { return true }
        return workbench.isPlanned(task) || task.isStarred
    }

    @MainActor
    func todayCount(_ workbench: Workbench) -> Int {
        open.filter { isToday($0, workbench) }.count
    }
}
