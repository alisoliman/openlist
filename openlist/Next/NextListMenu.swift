//
//  NextListMenu.swift
//  openlist
//

import SwiftUI

/// A list's commands, the same and in the same order wherever the list is
/// right-clicked, as every task surface shares `NXTaskMenu`: the sidebar, a
/// Lists card, a nested list's row and the list's own "…" menu. A native
/// extra: the design has no list menus. A surface leaves out only what it
/// can't do (Open, on the list's own page) and adds only its own: the
/// sidebar's Rename in place, and the "…" menu's options for the page on
/// show, after the list's presentation and hours. The Inbox, in the
/// sidebar, has those a system list can: its presentation, hours, link,
/// copy and export.
struct NXListMenu<Options: View>: View {
    enum Surface { case sidebar, gallery, page, childRow }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let list: TaskList
    let surface: Surface
    /// The sidebar's rename in place.
    var rename: (() -> Void)?
    @ViewBuilder var options: Options

    var body: some View {
        let workbench = env.workbench
        let navigator = env.navigator
        // Through its parent too; such a list comes back when the parent does.
        let archived = library.hierarchy.isArchived(list.id)
        if surface != .page {
            Button("Open") { workbench.go(workbench.route(for: list)) }
        }
        // Away from the page, the list opens to show it. The Inbox's tasks
        // presentation is its triage.
        Toggle(list.isSystemInbox ? "Show as Triage" : "Show Tasks Only",
               isOn: Binding(get: { navigator.listViewMode(for: list.id) == .tasks }, set: {
            navigator.setListViewMode($0 ? .tasks : .document, for: list.id)
            if surface != .page { workbench.go(workbench.route(for: list)) }
        }))
        Menu("Hours") { hoursItems }
            .accessibilityLabel("Hours: \(workbench.hours(for: list).title)")
        options
        if !list.isSystemInbox {
            Divider()
            // Over an open capture, beside the sidebar, the name field and
            // the save panel stand down, as File ▸'s do, so the card keeps
            // the keys and its draft.
            if let rename { Button("Rename List…", action: rename).disabled(workbench.captureOpen) }
            Button("Move List…") { env.listPendingMove = list }
            Button("New Child List") { workbench.createChildList(in: list) }
                .disabled(archived)
        }
        Divider()
        CopyItemLinkButton(target: .list(list.id))
        // Native extras: the design has neither copy nor export.
        Button("Copy as Markdown", action: copyMarkdown)
        Button("Export as Markdown…") { workbench.exportMarkdown(list) }
            .disabled(workbench.captureOpen)
        if !list.isSystemInbox {
            Divider()
            Button("Duplicate") { workbench.duplicateList(list) }
            Button("Use as Template…") { env.templateCopyRequest = TemplateCopyRequest(source: .list(list.id)) }
            Divider()
            // Nested lists show under their parent, so only top-level ones can be pinned.
            if !archived && library.hierarchy.parent(of: list.id) == nil {
                Button(list.isPinned ? "Remove from Sidebar" : "Pin to Sidebar") { workbench.setPinned(!list.isPinned, for: list) }
            }
            if list.isArchived || !archived {
                Button(list.isArchived ? "Unarchive List" : "Archive List") { workbench.setArchived(!list.isArchived, for: list) }
                    .help("Archived lists stay here and stop contributing tasks or reminders.")
            }
            Divider()
            Button("Delete List", role: .destructive) { env.requestDeleteList(list) }
        }
    }

    /// Which hours Plan and Start working use for this list, and where they're set.
    @ViewBuilder
    private var hoursItems: some View {
        let workbench = env.workbench
        Picker("Plan and Start working use", selection: Binding(get: { workbench.hours(for: list) },
                                                                set: { workbench.setHours($0, for: list.id) })) {
            ForEach(AvailabilityCategory.allCases) { category in
                let summary = NXHours.summary(env.calendar.preferences.profile(for: category), calendar: env.settings.calendar)
                Text("\(category.title) Hours · \(summary)").tag(category)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Edit Hours in Settings…") { workbench.go(.settings) }
    }

    /// The list's document on the clipboard, as Export writes it, said in the tray.
    private func copyMarkdown() {
        guard MarkdownExporter.copyToPasteboard(list: list, store: env.store) else { return }
        env.workbench.showTray("Copied \(NXFormat.quoted(list.displayTitle)) as Markdown", icon: "doc.on.clipboard")
    }
}

extension NXListMenu where Options == EmptyView {
    init(list: TaskList, surface: Surface, rename: (() -> Void)? = nil) {
        self.init(list: list, surface: surface, rename: rename) { EmptyView() }
    }
}
