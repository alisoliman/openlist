//
//  NextSidebarActions.swift
//  openlist
//
//  List and sidebar changes the sidebar and Lists gallery make, each with undo.
//

import Foundation

extension Workbench {
    /// A new list at the end of a section.
    func createList(in section: SidebarSection) {
        let list = makeUntitledList(in: section)
        announceCreated(list, in: section.displayTitle)
    }

    /// An empty list as the design makes one: 📝 in the current accent.
    func makeUntitledList(in section: SidebarSection?) -> TaskList {
        store.createList(title: "Untitled list", icon: "📝", accent: settings.accent.listAccent, in: section)
    }

    /// A new list nested under another.
    func createChildList(in parent: TaskList) {
        guard let list = store.createChildList(in: parent) else { return }
        announceCreated(list, in: parent.displayTitle)
    }

    private func announceCreated(_ list: TaskList, in place: String) {
        let id = list.id
        let label = "Created “\(list.displayTitle)” in \(place)"
        registerListCreationUndo(label, listID: id)
        snap(label, icon: "plus.circle.fill", tone: .accent, ids: [])
        pulse(list: id)
        namingListID = id
        go(.list(id))
    }

    /// Shows a top-level list in the sidebar or takes it off. Undo puts a
    /// removed list back where it sat, in its section or under "Other lists".
    func setPinned(_ pinned: Bool, for list: TaskList) {
        guard list.isPinned != pinned, !list.isSystemInbox else { return }
        let id = list.id
        let sectionID = list.sectionID
        let below = store.allLists()
            .filter { $0.isPinned && $0.sectionID == sectionID && $0.sidebarIndex > list.sidebarIndex }
            .min { $0.sidebarIndex < $1.sidebarIndex }?.id
        let apply: @MainActor (Workbench, Bool) -> Void = { workbench, target in
            guard let list = workbench.store.list(id: id) else { return }
            // Pinning a list that wasn't in the sidebar files it into the
            // default section; only undoing a removal restores its old place.
            guard target, !pinned else {
                workbench.store.setPinned(target, for: list)
                return
            }
            if let sectionID, workbench.store.allSections().contains(where: { $0.id == sectionID }) {
                workbench.store.move(list: list, toSection: sectionID, above: workbench.store.list(id: below))
            } else {
                // It sat under "Other lists", or its section has since been
                // deleted: re-pin it there. Unpinning kept its sidebarIndex,
                // so it returns to its old place.
                list.isPinned = true
                list.touch()
                workbench.store.save()
            }
        }
        apply(self, pinned)
        let label = pinned ? "Added “\(list.displayTitle)” to the sidebar" : "Removed “\(list.displayTitle)” from the sidebar"
        registerUndo(label, undo: { apply($0, !pinned) }, redo: { apply($0, pinned) })
        snap(label, icon: pinned ? "pin" : "pin.slash", tone: .neutral, ids: [])
    }

    /// Archived lists keep their tasks but stop contributing work or reminders.
    func setArchived(_ archived: Bool, for list: TaskList) {
        guard list.isArchived != archived, !list.isSystemInbox else { return }
        let id = list.id
        let apply: @MainActor (Workbench, Bool) -> Void = { workbench, archived in
            guard let list = workbench.store.list(id: id) else { return }
            workbench.store.setArchived(archived, for: list)
            workbench.calendar.storeDidChange()
        }
        apply(self, archived)
        let label = archived ? "Archived “\(list.displayTitle)”" : "Unarchived “\(list.displayTitle)”"
        registerUndo(label, undo: { apply($0, !archived) }, redo: { apply($0, archived) })
        snap(label, icon: archived ? "archivebox" : "tray.and.arrow.up", tone: .neutral, ids: [])
    }

    /// Icon & Colour…: the emoji or colour a list shows, each pick one change.
    func setAppearance(icon: String? = nil, accent: ListAccent? = nil, for list: TaskList) {
        let changesIcon = icon != nil && icon != list.icon
        let changesAccent = accent != nil && accent != list.accent
        guard changesIcon || changesAccent else { return }
        let id = list.id
        let before = (icon: list.icon, accent: list.accent)
        let apply: @MainActor (Workbench, String?, ListAccent?) -> Void = { workbench, icon, accent in
            guard let list = workbench.store.list(id: id) else { return }
            workbench.store.setAppearance(icon: icon, accent: accent, for: list)
        }
        apply(self, icon, accent)
        let label = icon.map { "\(NXFormat.quoted(list.displayTitle)) icon → \($0)" }
            ?? "\(NXFormat.quoted(list.displayTitle)) colour → \(accent?.title ?? "")"
        registerUndo(label, undo: { apply($0, icon.map { _ in before.icon }, accent.map { _ in before.accent }) },
                     redo: { apply($0, icon, accent) })
        snap(label, icon: icon == nil ? "paintpalette" : "face.smiling", tone: .accent, ids: [])
    }
}

private extension NextAccent {
    /// The list colour closest to this accent, for lists made in it.
    var listAccent: ListAccent {
        switch self {
        case .violet: .violet
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        }
    }
}
