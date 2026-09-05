//
//  Attachment.swift
//  openlist
//

import Foundation
import SwiftData

/// A file attached to a task's detail page. The file itself is copied into the
/// app's Application Support directory so the reference survives the original
/// being moved or deleted.
@Model
final class Attachment {
    var id: UUID = UUID()
    /// The task block this file hangs off.
    var blockID: UUID?
    var filename: String = ""
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
        sortIndex: Double = 0
    ) {
        self.id = UUID()
        self.blockID = blockID
        self.filename = filename
        self.displayName = displayName
        self.contentType = contentType
        self.byteCount = byteCount
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}

extension Attachment {
    var url: URL { MediaStore.shared.url(for: filename) }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var isImage: Bool { contentType.hasPrefix("image/") }
}
