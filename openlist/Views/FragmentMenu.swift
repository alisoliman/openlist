import AppKit
import SwiftUI

struct FragmentCopyMenu: View {
    let blockID: UUID
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button("Copy content and descendants") { copy(markdownOnly: false) }
            .help("Copy the complete subtree, formatting, notes, and files. Pasting clears schedules unless explicitly included.")
        Button("Copy subtree as Markdown") { copy(markdownOnly: true) }
            .help("Copy this subtree as readable Markdown. File bytes are available only with Copy content and descendants.")
    }

    private func copy(markdownOnly: Bool) {
        do {
            try FragmentClipboard.copy([blockID], store: env.store, markdownOnly: markdownOnly)
            if markdownOnly {
                env.store.editorNotice = "Subtree copied as Markdown. Images and files are described as text; use Copy content and descendants to include their bytes."
            }
        } catch { env.store.editorNotice = error.localizedDescription }
    }
}

struct FragmentPasteMenu: View {
    let document: DocumentContext
    var afterID: UUID?
    var onInserted: ([UUID]) -> Void = { _ in }
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button(afterID == nil ? "Paste content" : "Paste content after this block") { paste(includeSchedules: false) }
            .help("Keep content, completion, formatting, files, and labels. Clear dates, reminders, repeats, and calendar selections.")
        Button("Paste content including schedules") { paste(includeSchedules: true) }
            .help("Also include dates, reminders, repeat rules, and calendar selections. Past reminders are never replayed.")
    }

    private func paste(includeSchedules: Bool) {
        env.store.undoableEditorEdit(in: document.listID, name: "Paste content",
            undoManager: undoManager ?? NSApp.keyWindow?.undoManager, includingNewLabels: true) {
            do {
                let fragment = try FragmentClipboard.read()
                let ids = try env.store.pasteFragment(fragment, in: document, after: afterID, includeSchedules: includeSchedules)
                env.navigator.selection = Set(ids)
                onInserted(ids)
            } catch { env.store.editorNotice = error.localizedDescription }
        }
    }
}
