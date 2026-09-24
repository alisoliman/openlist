import Foundation

/// Version 1 local navigation contract. Only opaque library/item identities
/// leave the app; names, model persistent IDs and filesystem paths never do.
nonisolated struct LocalLink: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case task(UUID), list(UUID)

        var id: UUID {
            switch self { case let .task(id), let .list(id): id }
        }
        var route: String {
            switch self { case .task: "task"; case .list: "list" }
        }
    }

    static let productionScheme = "openlist"
    static let developmentScheme = "openlist-dev"
    #if OPENLIST_DEV
    static let scheme = developmentScheme
    #else
    static let scheme = productionScheme
    #endif

    let libraryID: UUID
    let target: Target

    func url(scheme: String = Self.scheme) -> URL {
        // Every component is generated from a closed vocabulary or a UUID.
        URL(string: "\(scheme)://v1/\(libraryID.uuidString.lowercased())/\(target.route)/\(target.id.uuidString.lowercased())")!
    }

    static func isLocal(_ url: URL) -> Bool {
        [productionScheme, developmentScheme].contains(url.scheme?.lowercased() ?? "")
    }

    static func parse(_ url: URL, scheme: String = Self.scheme) throws -> Self {
        guard url.scheme?.lowercased() == scheme else { throw LocalLinkError.wrongApp }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.percentEncodedPath.contains("%"),
              parts.percentEncodedHost == parts.host else { throw LocalLinkError.malformed }
        guard parts.host == "v1" else { throw LocalLinkError.unsupported }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 4, path[0].isEmpty, !path[2].isEmpty,
              let library = strictUUID(path[1]), let item = strictUUID(path[3]) else { throw LocalLinkError.malformed }
        let target: Target
        switch path[2] {
        case "task": target = .task(item)
        case "list": target = .list(item)
        default: throw LocalLinkError.unsupported
        }
        return Self(libraryID: library, target: target)
    }

    private static func strictUUID(_ value: Substring) -> UUID? {
        guard let id = UUID(uuidString: String(value)), id.uuidString.lowercased() == value.lowercased() else { return nil }
        return id
    }
}

nonisolated enum LocalLinkError: LocalizedError, Equatable {
    case malformed, unsupported, wrongApp, wrongLibrary, identityUnavailable, targetUnavailable

    var errorDescription: String? {
        switch self {
        case .malformed: "This link is not a valid Openlist item link. Copy a new link from the task or list menu."
        case .unsupported: "This link uses an unsupported Openlist version or destination. Only task and list links are supported."
        case .wrongApp: "This link belongs to a different app edition. Open production links with Openlist and development links with Openlist Dev."
        case .wrongLibrary: "This link belongs to a different local library. Open it on the Mac and in the library where it was copied."
        case .identityUnavailable: "This library’s link identity could not be read. Your content is still available. Restart Openlist before copying or opening item links."
        case .targetUnavailable: "This task or list is unavailable. It may have been deleted, changed to a text line, or removed from this library. Opening a link never restores content."
        }
    }
}
