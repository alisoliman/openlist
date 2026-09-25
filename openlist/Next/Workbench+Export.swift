//
//  Workbench+Export.swift
//  openlist
//

import Foundation

extension Workbench {
    /// A list's Export as Markdown…, from its "…" menu, the sidebar, Lists or
    /// ⇧⌘E: the save panel, then, once it's written, a line in the tray, as
    /// Copy as Markdown beside it says so there. A failure says why in the
    /// window's notice. A native extra: the design has no export.
    func exportMarkdown(_ list: TaskList) {
        guard MarkdownExporter.presentSavePanel(for: list, store: store) else { return }
        showTray("Exported \(NXFormat.quoted(list.displayTitle)) as Markdown", icon: "square.and.arrow.up")
    }
}
