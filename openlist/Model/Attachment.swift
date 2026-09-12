//
//  Attachment.swift
//  openlist
//

import Foundation
import SwiftData

/// An imported file, stored with its record for iCloud and cached locally for
/// opening and export. Moving the original file does not affect the attachment.
@Model
final class Attachment {
    var id: UUID = UUID()
    /// The task block this file hangs off.
    var blockID: UUID?
    var filename: String = ""
    @Attribute(.externalStorage) var contentData: Data?
    var displayName: String = ""
    var contentType: String = ""
    var byteCount: Int = 0
    var sortIndex: Double = 0
    var createdAt: Date = Date.now

    init(
        blockID: UUID,
        filename: String,
        displayName: String,
        contentType: String,
        byteCount: Int,
        sortIndex: Double = 0,
        contentData: Data? = nil
    ) {
        self.id = UUID()
        self.blockID = blockID
        self.filename = filename
        self.contentData = contentData
        self.displayName = displayName
        self.contentType = contentType
        self.byteCount = byteCount
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}

extension Attachment {
    func fileURL() throws -> URL {
        try MediaStore.shared.materialize(filename: filename, data: contentData)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var isImage: Bool { contentType.hasPrefix("image/") }
}
