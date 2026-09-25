//
//  TaskList.swift
//  openlist
//

import Foundation
import SwiftData

/// A list document. In Superlist a list is not merely a checklist — it is a
/// rich document that happens to contain tasks, so its content lives in
/// `Block` rows keyed by `listID`.
@Model
final class TaskList {
    var id: UUID = UUID()

    /// Retained records keep their identity and payload until explicitly erased.
    var trashID: UUID?
    /// Present on the root; retained after recovery to explain its former location.
    var trashMetadataData: Data?
    /// The single owning document; nil means top level. Pins and links are independent.
    var parentListID: UUID?
    var title: String = ""
    /// Emoji shown in the sidebar and list header.
    var icon: String = "📋"
    /// Raw `ListAccent` for the list's tint.
    var accentRaw: String = ListAccent.graphite.rawValue
    var summary: String = ""

    /// Independent, optional local image ownership; bytes also travel with sync.
    var coverFilename: String?
    @Attribute(.externalStorage) var coverData: Data?
    var coverMetadataData: Data?
    /// nil preserves the compact default for migrated lists.
    var coverPresentationRaw: String?

    /// Inbox is a singleton system list that receives unfiled tasks.
    var isSystemInbox: Bool = false
    /// Retained aliases route late-arriving records from another Mac's Inbox.
    var mergedIntoID: UUID?

    /// Position among all lists.
    var sortIndex: Double = 0
    /// Position within its sidebar section.
    var sidebarIndex: Double = 0
    /// Section this list is pinned under in the sidebar. `nil` means the list
    /// is not pinned and is only reachable from the Lists view.
    var sectionID: UUID?
    var isPinned: Bool = false
    var isArchived: Bool = false

    /// Per-list display preferences.
    var sortingRaw: String = ListSorting.manual.rawValue
    /// Kept for migration and older app versions. Legacy hidden lists keep
    /// their override; the historical true default adopts app inheritance.
    var showsCompleted: Bool = true
    var completedVisibilityRaw: String?
    /// The weekly availability inherited by this list's tasks.
    var availabilityCategoryRaw: String = "work"

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var lastOpenedAt: Date?

    init(
        title: String = "",
        icon: String = "📋",
        accent: ListAccent = .graphite,
        isSystemInbox: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.accentRaw = accent.rawValue
        self.isSystemInbox = isSystemInbox
        self.completedVisibilityRaw = CompletedVisibility.inherit.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension TaskList {
    static var availablePredicate: Predicate<TaskList> {
        #Predicate<TaskList> { $0.trashID == nil && $0.mergedIntoID == nil }
    }
    static var activePredicate: Predicate<TaskList> {
        #Predicate<TaskList> { $0.trashID == nil && !$0.isArchived && $0.mergedIntoID == nil }
    }

    var isTrashed: Bool { trashID != nil }
    @MainActor var isEffectivelyArchived: Bool { (try? ownershipAncestors().contains { $0.isArchived }) ?? true }
    @MainActor var isEffectivelyTrashed: Bool { (try? ownershipAncestors().contains { $0.isTrashed }) ?? true }

    @MainActor private func ownershipAncestors() throws -> [TaskList] {
        var result = [self], seen: Set<UUID> = [id]
        var next = isSystemInbox ? nil : parentListID
        while let id = next, seen.insert(id).inserted, let context = modelContext {
            guard let parent = try context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id })).first else { break }
            result.append(parent)
            next = parent.isSystemInbox ? nil : parent.parentListID
        }
        return result
    }
    var trashMetadata: TrashMetadata? {
        trashMetadataData.flatMap { try? JSONDecoder().decode(TrashMetadata.self, from: $0) }
    }

    enum CompletedVisibility: String, CaseIterable, Identifiable {
        case inherit, show, hide
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inherit: "Use app default"
            case .show: "Show completed"
            case .hide: "Hide completed"
            }
        }
    }

    var completedVisibility: CompletedVisibility {
        get {
            if let raw = completedVisibilityRaw, let value = CompletedVisibility(rawValue: raw) {
                return value
            }
            // Old data cannot distinguish explicitly shown from the historical
            // true default. Adopt inheritance for true, preserve explicit hide.
            // Inbox previously always followed the app setting.
            return isSystemInbox || showsCompleted ? .inherit : .hide
        }
        set {
            completedVisibilityRaw = newValue.rawValue
            if newValue != .inherit { showsCompleted = newValue == .show }
        }
    }

    func showsCompleted(default defaultValue: Bool) -> Bool {
        switch completedVisibility {
        case .inherit: defaultValue
        case .show: true
        case .hide: false
        }
    }

    var accent: ListAccent {
        get { ListAccent(rawValue: accentRaw) ?? .graphite }
        set { accentRaw = newValue.rawValue }
    }

    var sorting: ListSorting {
        get { ListSorting(rawValue: sortingRaw) ?? .manual }
        set { sortingRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled list" : trimmed
    }

    /// The emoji shown for a list; Inbox has a fixed one.
    var glyph: String {
        if isSystemInbox { return "📥" }
        return icon.isEmpty ? "📋" : icon
    }

    /// The list's colour as 0xRRGGBB. Inbox draws in its own blue throughout
    /// the app, whatever accent it has stored.
    var displayAccentHex: UInt32 { isSystemInbox ? ListAccent.inboxHex : accent.hex }

    func touch() { updatedAt = .now }
}

/// How tasks are ordered in a document's contiguous runs or its task-only queue.
enum ListSorting: String, Codable, CaseIterable, Sendable {
    case manual
    case dueDate
    case createdAt
    case alphabetical
    case priority

    var title: String {
        switch self {
        case .manual: "Manual"
        case .dueDate: "Due date"
        case .createdAt: "Date created"
        case .alphabetical: "Alphabetical"
        case .priority: "Priority"
        }
    }

}

extension TaskList {
    var coverPresentation: ListCoverPresentation {
        coverPresentationRaw.flatMap(ListCoverPresentation.init(rawValue:)) ?? .compact
    }
    var coverMetadata: ListCoverMetadata? {
        coverMetadataData.flatMap { try? JSONDecoder().decode(ListCoverMetadata.self, from: $0) }
    }

    /// Unknown or partial payloads must remain recoverable, never disappear in a copy.
    func validatedCover() throws -> (filename: String, metadata: ListCoverMetadata)? {
        try ListCoverMetadata.validatePayload(filename: coverFilename, data: coverData, metadataData: coverMetadataData,
                               presentationRaw: coverPresentationRaw)
    }

}
