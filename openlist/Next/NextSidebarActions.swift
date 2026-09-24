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
        snap(label, icon: "plus.circle", tone: .accent, ids: [])
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

// MARK: Copies and moves

/// A sidebar section taken out, as Undo last brought it back or Redo took it
/// out again, for the step after.
private final class SectionRemoval {
    var deleted: DeletedSidebarSection?
    init(_ deleted: DeletedSidebarSection? = nil) { self.deleted = deleted }
}

extension Workbench {
    /// Duplicate in the sidebar and Lists: a copy of the list, its nested
    /// lists and everything in them, right after it, as one change the tray
    /// can undo. The copy opens. One that failed says why in a notice and
    /// leaves the list where it is.
    func duplicateList(_ list: TaskList) {
        document?.commitLine()
        let copy = store.duplicateList(list)
        guard copy.id != list.id else { return }
        announceListCopy(of: list, "Duplicated \(NXFormat.quoted(list.displayTitle))", copyID: copy.id)
    }

    /// Use as Template…'s copy of a list, reset to start again, as one change
    /// the tray can undo. The copy opens.
    func copyListAsTemplate(_ id: UUID, keepingRecurrence: Bool) throws {
        document?.commitLine()
        guard let list = store.list(id: id) else { throw CopyError.unavailable }
        let copyID = try store.copyList(list, mode: .template(keepingRecurrence: keepingRecurrence))
        announceListCopy(of: list, "Copied \(NXFormat.quoted(list.displayTitle)) as a template", copyID: copyID)
    }

    /// Undo takes the copy to Trash, with anything added to it since.
    private func announceListCopy(of list: TaskList, _ label: String, copyID: UUID) {
        registerListCreationUndo(label, listID: copyID)
        snap(label, icon: "plus.square.on.square", tone: .accent, ids: [copyID])
        pulse(list: copyID)
        go(.list(copyID))
    }

    /// Move List…: the list and its nested lists under another, or at the
    /// top level, as one change the tray can undo, as the design's move
    /// offers the list it went to. False, with the Store's notice saying
    /// why, when it can't go there.
    @discardableResult
    func moveList(_ list: TaskList, under parentID: UUID?) -> Bool {
        let id = list.id
        let previous = list.parentListID
        guard previous != parentID else { return true }
        guard store.moveList(list, under: parentID) else { return false }
        let parent = parentID.flatMap { store.list(id: $0) }
        let label = parent.map { "Moved \(NXFormat.quoted(list.displayTitle)) under \(NXFormat.quoted($0.displayTitle))" }
            ?? "Moved \(NXFormat.quoted(list.displayTitle)) to the top level"
        let move: @MainActor (Workbench, UUID?) -> Bool = { workbench, parentID in
            guard let list = workbench.store.list(id: id) else { return false }
            return workbench.store.moveList(list, under: parentID)
        }
        snap(label, icon: "folder", tone: .accent, ids: [id],
             destination: parent.map { TrayDestination(label: "Open \($0.displayTitle)", route: route(for: $0)) },
             undo: { move($0, previous) }, redo: { move($0, parentID) })
        pulse(list: id)
        return true
    }

    /// A top-level list dragged in the sidebar, above another or to the end
    /// of a section, as one change the tray can undo. Undo puts back only
    /// the lists it moved, and only those still where it left them.
    func moveList(_ list: TaskList, toSection sectionID: UUID?, above target: TaskList?) {
        let before = store.sidebarPlacements()
        let from = list.sectionID
        store.move(list: list, toSection: sectionID, above: target)
        let after = store.sidebarPlacements()
        let moved = after.filter { before[$0.key] != $0.value }
        guard !moved.isEmpty else { return }
        let undone = before.filter { moved[$0.key] != nil }
        let section = store.allSections().first { $0.id == store.resolvedSectionID(sectionID) }
        let place = section?.displayTitle ?? "Other lists"
        let label = "Moved \(NXFormat.quoted(list.displayTitle)) " + (store.resolvedSectionID(sectionID) == from ? "in" : "to") + " \(place)"
        registerUndo(label, undo: { $0.store.applySidebarPlacements(undone, expecting: moved) },
                     redo: { $0.store.applySidebarPlacements(moved, expecting: undone) })
        snap(label, icon: "folder", tone: .accent, ids: [list.id])
        pulse(list: list.id)
    }

    // MARK: Sections

    /// File ▸ New Section: a section at the end of the sidebar, as one change
    /// the tray can undo, whose name field opens there.
    func createSection() {
        let section = store.createSection()
        let id = section.id
        let taken = SectionRemoval()
        snap("Created \(NXFormat.quoted(section.displayTitle))", icon: "folder.badge.plus", tone: .accent, ids: [], undo: { workbench in
            // Deleted meanwhile, it's gone already.
            guard let section = workbench.store.allSections().first(where: { $0.id == id }) else { return true }
            guard let deleted = workbench.store.removeSection(section) else { return false }
            taken.deleted = deleted
            return true
        }, redo: { workbench in
            guard let deleted = taken.deleted else { return true }
            taken.deleted = nil
            return workbench.store.restoreSection(deleted)
        })
        if !showsSidebar { toggleSidebar() }
        namingSectionID = id
    }

    /// A section's Delete, as one change the tray can undo: its lists stay in
    /// the sidebar under "Other lists", and Undo files them back where they sat.
    func deleteSection(_ section: SidebarSection) {
        let title = section.displayTitle
        guard let deleted = store.removeSection(section) else { return }
        let taken = SectionRemoval(deleted)
        let label = deleted.lists.isEmpty ? "Deleted \(NXFormat.quoted(title))"
            : "Deleted \(NXFormat.quoted(title)) · its lists moved to Other lists"
        snap(label, icon: "folder.badge.minus", tone: .red, ids: [], undo: { workbench in
            guard let deleted = taken.deleted else { return true }
            return workbench.store.restoreSection(deleted)
        }, redo: { workbench in
            // Deleted again meanwhile, it's gone already.
            guard let section = workbench.store.allSections().first(where: { $0.id == deleted.id }) else { return true }
            guard let removed = workbench.store.removeSection(section) else { return false }
            taken.deleted = removed
            return true
        })
    }

    /// A section's name written in place in the sidebar: one Undo step,
    /// logged as a list's rename is.
    func renameSection(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let section = store.allSections().first(where: { $0.id == id }), section.title != title else { return }
        let previous = section.title
        let apply: @MainActor (Workbench, String) -> Void = { workbench, title in
            guard let section = workbench.store.allSections().first(where: { $0.id == id }) else { return }
            workbench.store.rename(section, to: title)
        }
        apply(self, title)
        let label = "Renamed section to \(NXFormat.quoted(title))"
        registerUndo(label, undo: { apply($0, previous) }, redo: { apply($0, title) })
        logEdit(label, ids: [])
    }

    // MARK: List options

    /// The "…" menu's Sort, each pick one change the tray can undo.
    func setSorting(_ sorting: ListSorting, for list: TaskList) {
        guard list.sorting != sorting else { return }
        let id = list.id
        let previous = list.sorting
        let apply: @MainActor (Workbench, ListSorting) -> Void = { workbench, sorting in
            guard let list = workbench.store.list(id: id) else { return }
            workbench.store.setSorting(sorting, for: list)
        }
        apply(self, sorting)
        let order = switch sorting {
        case .manual: "by hand"
        case .dueDate: "by due date"
        case .createdAt: "by date created"
        case .alphabetical: "alphabetically"
        case .priority: "by priority"
        }
        let label = "Sorted \(NXFormat.quoted(list.displayTitle)) \(order)"
        registerUndo(label, undo: { apply($0, previous) }, redo: { apply($0, sorting) })
        snap(label, icon: "arrow.up.arrow.down", tone: .accent, ids: [id])
    }

    /// The "…" menu's Completed Tasks, each pick one change the tray can undo.
    func setCompletedVisibility(_ visibility: TaskList.CompletedVisibility, for list: TaskList) {
        guard list.completedVisibility != visibility else { return }
        let id = list.id
        let previous = list.completedVisibility
        let apply: @MainActor (Workbench, TaskList.CompletedVisibility) -> Void = { workbench, visibility in
            guard let list = workbench.store.list(id: id) else { return }
            workbench.store.setCompletedVisibility(visibility, for: list)
        }
        apply(self, visibility)
        let name = NXFormat.quoted(list.displayTitle)
        let label = switch visibility {
        case .show: "\(name) shows completed tasks"
        case .hide: "\(name) hides completed tasks"
        case .inherit: "\(name) uses the app’s setting for completed tasks"
        }
        registerUndo(label, undo: { apply($0, previous) }, redo: { apply($0, visibility) })
        snap(label, icon: visibility == .hide ? "eye.slash" : "eye", tone: .neutral, ids: [id])
    }

    /// The "…" menu's Cover: an image added, replaced or removed, or how it
    /// shows, as one change the tray can undo. The image comes back with its
    /// bytes even once the cache has let it go. Throws, changing nothing,
    /// when the Store can't make the change.
    func setCover(of list: TaskList, from source: URL) throws {
        let label = list.coverFilename == nil ? "Added a cover to \(NXFormat.quoted(list.displayTitle))"
            : "Replaced the cover of \(NXFormat.quoted(list.displayTitle))"
        try changeCover(of: list, label: label, tone: .accent) { try $0.setListCover($1, from: source) }
    }

    func setCoverPresentation(_ presentation: ListCoverPresentation, of list: TaskList) throws {
        guard list.coverPresentation != presentation else { return }
        try changeCover(of: list, label: "\(NXFormat.quoted(list.displayTitle)) cover → \(presentation.title)", tone: .accent) {
            try $0.setListCoverPresentation($1, presentation: presentation)
        }
    }

    func removeCover(of list: TaskList) throws {
        try changeCover(of: list, label: "Removed the cover of \(NXFormat.quoted(list.displayTitle))", tone: .red) {
            try $0.removeListCover($1)
        }
    }

    private func changeCover(of list: TaskList, label: String, tone: TrayTone,
                             _ change: (Store, TaskList) throws -> Void) throws {
        let id = list.id
        let before = store.listCoverState(list)
        try change(store, list)
        guard let changed = store.list(id: id) else { return }
        let after = store.listCoverState(changed)
        guard after != before else { return }
        let put: @MainActor (Workbench, ListCoverState) -> Bool = { workbench, state in
            guard let list = workbench.store.list(id: id) else { return false }
            do {
                try workbench.store.restoreListCover(list, to: state)
                return true
            } catch {
                workbench.store.editorNotice = "The cover could not be changed back. \(error.localizedDescription)"
                return false
            }
        }
        snap(label, icon: "photo", tone: tone, ids: [id], undo: { put($0, before) }, redo: { put($0, after) })
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
