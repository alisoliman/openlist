import Foundation
import Observation
import SwiftData

/// Holds incoming deliveries until both bootstrap and the main window are
/// ready. A delivery is consumed once; explicitly opening the same URL later
/// remains a new navigation request.
@Observable @MainActor
final class LocalLinkNavigation {
    private let libraryID: UUID?
    private let navigator: Navigator
    @ObservationIgnored private var pending: [URL] = []
    @ObservationIgnored private var resolve: ((LocalLink.Target) throws -> ContentReveal)?
    @ObservationIgnored private var isWindowReady = false
    var error: LocalLinkError?

    init(libraryID: UUID?, navigator: Navigator) {
        self.libraryID = libraryID
        self.navigator = navigator
    }

    func receive(_ url: URL) {
        pending.append(url)
        drain()
    }

    func storeReady(resolve: @escaping (LocalLink.Target) throws -> ContentReveal) {
        self.resolve = resolve
        drain()
    }

    func windowReady(_ value: Bool) {
        isWindowReady = value
        drain()
    }

    func link(to target: LocalLink.Target) throws -> URL {
        guard let libraryID else { throw LocalLinkError.identityUnavailable }
        guard let resolve else { throw LocalLinkError.targetUnavailable }
        _ = try resolve(target)
        return LocalLink(libraryID: libraryID, target: target).url()
    }

    private func drain() {
        guard isWindowReady, let resolve else { return }
        let deliveries = pending
        pending.removeAll()
        for url in deliveries {
            do {
                let link = try LocalLink.parse(url)
                guard let libraryID else { throw LocalLinkError.identityUnavailable }
                guard link.libraryID == libraryID else { throw LocalLinkError.wrongLibrary }
                let reveal = try resolve(link.target)
                error = nil
                navigator.isSearchOpen = false
                navigator.isCommandPaletteOpen = false
                navigator.isShortcutSheetOpen = false
                navigator.reveal(reveal)
            } catch {
                self.error = error as? LocalLinkError ?? .targetUnavailable
            }
        }
    }

    static func resolve(_ target: LocalLink.Target, blocks: [Block], lists: [TaskList]) throws -> ContentReveal {
        let destination: SearchDestination
        switch target {
        case let .task(id):
            guard blocks.contains(where: { !$0.isDeleted && $0.id == id && $0.isTask }) else {
                throw LocalLinkError.targetUnavailable
            }
            destination = .block(id)
        case let .list(id): destination = .list(id)
        }
        do {
            var request = try ContentReveal.resolve(destination, blocks: blocks, lists: lists)
            request.source = .localLink
            return request
        } catch { throw LocalLinkError.targetUnavailable }
    }
}
