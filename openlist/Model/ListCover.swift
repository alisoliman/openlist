import Foundation

nonisolated enum ListCoverPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact, hidden
    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Hidden" }
}

nonisolated struct ListCoverMetadata: Codable, Equatable, Sendable {
    var version = 1
    var displayName: String
    var contentType: String
    var byteCount: Int
    var pixelWidth: Int
    var pixelHeight: Int

    func validate() throws {
        guard version == 1 else { throw ListCoverError.unavailable }
        guard !displayName.isEmpty, contentType.hasPrefix("image/"),
              byteCount > 0, byteCount <= 20 * 1_024 * 1_024,
              pixelWidth > 0, pixelHeight > 0, pixelWidth <= 16_384, pixelHeight <= 16_384,
              pixelWidth * pixelHeight <= 40_000_000 else { throw ListCoverError.invalid }
    }
}

nonisolated enum ListCoverError: LocalizedError {
    case invalid, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "Choose a readable image up to 20 MB and 40 megapixels, with each side no larger than 16,384 pixels."
        case .unavailable: "The list cover is incomplete or unavailable. Its existing data has been kept."
        }
    }
}

extension ListCoverMetadata {
    nonisolated static func validatePayload(filename: String?, data: Data?, metadataData: Data?,
                                         presentationRaw: String?) throws -> (filename: String, metadata: ListCoverMetadata)? {
        if let presentationRaw, ListCoverPresentation(rawValue: presentationRaw) == nil { throw ListCoverError.unavailable }
        guard let filename else {
            guard data == nil, metadataData == nil else { throw ListCoverError.unavailable }
            return nil
        }
        guard !filename.isEmpty, filename != ".", filename != "..", (filename as NSString).lastPathComponent == filename,
              let metadataData, let metadata = try? JSONDecoder().decode(ListCoverMetadata.self, from: metadataData) else {
            throw ListCoverError.unavailable
        }
        try metadata.validate()
        if let data, data.count != metadata.byteCount { throw ListCoverError.unavailable }
        return (filename, metadata)
    }
}
