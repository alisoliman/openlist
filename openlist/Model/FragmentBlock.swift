import Foundation
import ImageIO

nonisolated struct FragmentBlock: Codable, Equatable, Sendable {
    var id: UUID
    var parentID: UUID?
    var kind: String
    var text: String
    var styles: [FragmentTextStyle] = []
    var isCollapsed = false
    var isCompleted = false
    var completedAt: Date?
    var dueDate: Date?
    var includesTime = false
    var reminderAt: Date?
    var recurrence: Recurrence?
    var selectedForDay: Date?
    var deferredUntil: Date?
    var isStarred = false
    var priority = 0
    var labelIDs: [UUID] = []
    var note = ""
    var schedulingEstimateMinutes = 0
    var keepsSessionsTogether = false
    var tracksAwayFromMac = false
    var image: FragmentMedia?
    var mediaWidth: Double = 0
    var mediaHeight: Double = 0
    var mediaCaption = ""
    var attachments: [FragmentAttachment] = []

    func validate(labelIDs available: Set<UUID>) throws {
        guard ["paragraph", "heading1", "heading2", "heading3", "task", "bullet", "numbered", "quote", "code", "divider", "image"].contains(kind),
              (0...3).contains(priority), (0...525_600).contains(schedulingEstimateMinutes),
              text.utf8.count <= 1_048_576, note.utf8.count <= 1_048_576,
              mediaCaption.utf8.count <= 65_536, styles.count <= 10_000,
              attachments.count <= 1_000,
              Set(labelIDs).count == labelIDs.count, Set(labelIDs).isSubset(of: available),
              mediaWidth.isFinite, mediaHeight.isFinite, mediaWidth >= 0, mediaHeight >= 0 else {
            throw FragmentError.invalid("An item has invalid content, metadata, or media references.")
        }
        for date in [completedAt, dueDate, reminderAt, selectedForDay, deferredUntil, recurrence?.endDate].compactMap({ $0 }) {
            guard date.timeIntervalSinceReferenceDate.isFinite else { throw FragmentError.invalid("A date is invalid.") }
        }
        if let image {
            try image.validate()
            guard let source = CGImageSourceCreateWithData(image.data as CFData, nil), CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0,
                  width.doubleValue * height.doubleValue <= 100_000_000,
                  CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
                throw FragmentError.invalid("An image is corrupt, unsupported, or exceeds 100 million pixels.")
            }
        }
        var end = 0
        for style in styles {
            guard style.location >= end, style.length > 0,
                  style.location <= text.utf16.count, style.length <= text.utf16.count - style.location,
                  Range(NSRange(location: style.location, length: style.length), in: text) != nil,
                  style.link.map({ $0.utf8.count <= 8_192 && URL(string: $0) != nil }) ?? true else {
                throw FragmentError.invalid("Text formatting has an invalid range or link.")
            }
            end = style.location + style.length
        }
        if let rule = recurrence {
            guard (1...10_000).contains(rule.interval), rule.weekdays.isSubset(of: Set(1...7)),
                  rule.dayOfMonth.map({ (1...31).contains($0) }) ?? true,
                  rule.occurrenceLimit.map({ $0 > 0 }) ?? true, rule.completedOccurrences == 0 else {
                throw FragmentError.invalid("A repeat rule contains invalid values or past occurrence progress.")
            }
        }
        for attachment in attachments {
            guard attachment.displayName.utf8.count <= 4_096, attachment.contentType.utf8.count <= 1_024 else {
                throw FragmentError.invalid("A file description is too long.")
            }
        }
    }
}

nonisolated struct FragmentLabel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var accent: String
}

nonisolated struct FragmentMedia: Codable, Equatable, Sendable {
    /// Extension only; paths and URLs are never accepted or resolved.
    var fileExtension: String
    var data: Data
    func validate() throws {
        guard fileExtension.utf8.count <= 32,
              fileExtension.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_+-".unicodeScalars.contains($0) }) else {
            throw FragmentError.invalid("A media filename contains a path or unsupported extension.")
        }
        guard data.count <= DocumentFragment.maximumAssetBytes else { throw FragmentError.tooLarge }
    }
}

nonisolated struct FragmentAttachment: Codable, Equatable, Sendable {
    var displayName: String
    var contentType: String
    var media: FragmentMedia
}
