import Foundation
import SwiftData

extension Store {
    /// Editors and drag payloads may still hold a system ID from before an
    /// import. Resolve it at write boundaries as well as during reconciliation.
    func resolvedListID(_ id: UUID?) -> UUID? {
        guard let id else { return nil }
        return list(id: id)?.id ?? id
    }

    func resolvedSectionID(_ id: UUID?) -> UUID? {
        guard let id else { return nil }
        do {
            let section = try context.fetch(FetchDescriptor<SidebarSection>(predicate: #Predicate { $0.id == id })).first
            return section?.mergedIntoID ?? id
        } catch {
            persistenceError = "The sidebar section could not be read. \(error.localizedDescription)"
            return id
        }
    }

    func resolvedSection(_ section: SidebarSection) -> SidebarSection {
        guard let target = section.mergedIntoID else { return section }
        return allSections().first { $0.id == target } ?? section
    }

    /// CloudKit imports are not atomic across records. Keep losing system rows
    /// as aliases, so a task/section reference arriving in a later batch can
    /// still be routed. Ordinary user-created lists and sections are never merged.
    func reconcileSystemRecords() throws {
        let lists = try context.fetch(FetchDescriptor<TaskList>())
        let sections = try context.fetch(FetchDescriptor<SidebarSection>())
        let inboxes = lists.filter(\.isSystemInbox)
        let defaults = sections.filter(\.isDefault)

        func canonicalID(_ records: [(id: UUID, createdAt: Date, target: UUID?)]) -> UUID? {
            let known = Set(records.map { $0.id })
            let missing = records.compactMap { $0.target }.filter { !known.contains($0) }
            if let pending = missing.min(by: { $0.uuidString < $1.uuidString }) { return pending }
            // A fresh Mac's untouched defaults must not replace an existing
            // Inbox/section's identity and customized display settings.
            return records.min {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }?.id
        }

        if let winner = canonicalID(inboxes.map { ($0.id, $0.createdAt, $0.mergedIntoID) }) {
            let aliases = Set(inboxes.map(\.id).filter { $0 != winner })
            for inbox in inboxes {
                let target = inbox.id == winner ? nil : winner
                if inbox.mergedIntoID != target { inbox.mergedIntoID = target }
            }
            if !aliases.isEmpty {
                for block in try context.fetch(FetchDescriptor<Block>()) {
                    if let listID = block.listID, aliases.contains(listID) { block.listID = winner }
                }
                for event in try context.fetch(FetchDescriptor<ActivityEvent>()) {
                    if let listID = event.listID, aliases.contains(listID) { event.listID = winner }
                }
            }
        }

        if let winner = canonicalID(defaults.map { ($0.id, $0.createdAt, $0.mergedIntoID) }) {
            let aliases = Set(defaults.map(\.id).filter { $0 != winner })
            for section in defaults {
                let target = section.id == winner ? nil : winner
                if section.mergedIntoID != target { section.mergedIntoID = target }
            }
            for list in lists {
                if let sectionID = list.sectionID, aliases.contains(sectionID) { list.sectionID = winner }
            }
        }
    }

    /// Additive migration: copy legacy files into optional synced attributes,
    /// retaining every source file. Missing files are reported and retried, not
    /// replaced with empty bytes or marked as successfully migrated.
    func prepareForSync() {
        do {
            try reconcileSystemRecords()
            try migrateInboxMembership()
            let images = try context.fetch(FetchDescriptor<Block>(
                predicate: #Predicate { $0.mediaFilename != nil && $0.mediaData == nil }
            ))
            let attachments = try context.fetch(FetchDescriptor<Attachment>(
                predicate: #Predicate { $0.contentData == nil }
            ))
            var failures: [String] = []
            for image in images {
                guard let filename = image.mediaFilename else { continue }
                do {
                    image.mediaData = try MediaStore.shared.readFile(filename: filename)
                } catch {
                    failures.append("\(filename): \(error.localizedDescription)")
                }
            }
            for attachment in attachments {
                do {
                    attachment.contentData = try MediaStore.shared.readFile(filename: attachment.filename)
                } catch {
                    failures.append("\(attachment.displayName): \(error.localizedDescription)")
                }
            }
            syncPreparationError = failures.first.map {
                "\(failures.count) file(s) could not be prepared for iCloud. Local files were left intact. \($0)"
            }
            save()
        } catch {
            syncPreparationError = "Synced data could not be prepared. \(error.localizedDescription)"
        }
    }
}
