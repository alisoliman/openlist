import Foundation
import SwiftData

extension Store {
    func setListCover(_ list: TaskList, from source: URL) throws {
        let media = try MediaStore.shared.readCover(at: source)
        let metadata = ListCoverMetadata(displayName: media.displayName, contentType: media.contentType,
            byteCount: media.byteCount, pixelWidth: Int(media.pixelSize.width), pixelHeight: Int(media.pixelSize.height))
        let encoded = try JSONEncoder().encode(metadata)
        try mutateListCover(list, filename: media.filename, data: media.data, metadata: encoded,
                            presentation: list.coverPresentationRaw)
    }

    func removeListCover(_ list: TaskList) throws {
        try mutateListCover(list, filename: nil, data: nil, metadata: nil, presentation: nil)
    }

    func setListCoverPresentation(_ list: TaskList, presentation: ListCoverPresentation) throws {
        try mutateListCover(list, filename: list.coverFilename, data: list.coverData,
                            metadata: list.coverMetadataData, presentation: presentation.rawValue)
    }

    /// A list's cover as it is, with its bytes, which the cache may let go
    /// of once another replaces it, for Undo of a change to it.
    func listCoverState(_ list: TaskList) -> ListCoverState {
        ListCoverState(filename: list.coverFilename,
                       data: list.coverData ?? list.coverFilename.flatMap { MediaStore.shared.fileContents(filename: $0) },
                       metadata: list.coverMetadataData, presentation: list.coverPresentationRaw)
    }

    /// Puts a cover back as ``listCoverState(_:)`` read it, its file too.
    func restoreListCover(_ list: TaskList, to state: ListCoverState) throws {
        try mutateListCover(list, filename: state.filename, data: state.data, metadata: state.metadata,
                            presentation: state.presentation)
    }

    private func mutateListCover(_ list: TaskList, filename: String?, data: Data?, metadata: Data?, presentation: String?) throws {
        guard self.list(id: list.id) === list, !list.isDeleted, !list.isSystemInbox else { throw ListCoverError.unavailable }
        // Commit existing drafts first. A failed preflight has changed no cover fields or files.
        try persistChanges()
        let original = (list.coverFilename, list.coverData, list.coverMetadataData, list.coverPresentationRaw, list.updatedAt)
        let isNewFile = filename != nil && filename != original.0
        if isNewFile, let filename, let data { try MediaStore.shared.restoreFile(data, filename: filename) }
        do {
            list.coverFilename = filename
            list.coverData = data
            list.coverMetadataData = metadata
            list.coverPresentationRaw = presentation
            list.touch()
            try persistChanges()
        } catch {
            context.rollback()
            // SwiftData can leave attempted values in live view instances after rollback.
            list.coverFilename = original.0
            list.coverData = original.1
            list.coverMetadataData = original.2
            list.coverPresentationRaw = original.3
            list.updatedAt = original.4
            if isNewFile, let filename { try? MediaStore.shared.eraseCachedFile(filename: filename) }
            throw error
        }
        if let old = original.0, old != filename {
            // Cleanup is best effort after commit. A failed unlink keeps a harmless
            // cache; it must not report a successful persisted replacement as failed.
            if let referenced = try? referencedMediaFilenames(), !referenced.contains(old) {
                try? MediaStore.shared.eraseCachedFile(filename: old)
            }
        }
    }

    /// Every live and retained model participates in shared cache ownership.
    func referencedMediaFilenames() throws -> Set<String> {
        let lists = try context.fetch(FetchDescriptor<TaskList>()).filter { !$0.isDeleted }
        let blocks = try context.fetch(FetchDescriptor<Block>()).filter { !$0.isDeleted }
        let attachments = try context.fetch(FetchDescriptor<Attachment>()).filter { !$0.isDeleted }
        return Set(lists.compactMap(\.coverFilename) + blocks.compactMap(\.mediaFilename) + attachments.map(\.filename))
    }
}

/// A list's cover, bytes included, as Undo and Redo of a cover change put it.
struct ListCoverState: Equatable {
    var filename: String?
    var data: Data?
    var metadata: Data?
    var presentation: String?
}
