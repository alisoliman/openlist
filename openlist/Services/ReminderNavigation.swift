import Foundation
import Observation

/// Notification responses can arrive before bootstrap or while the window is
/// closed. Retain the latest explicit click until both destinations are ready.
@Observable @MainActor
final class ReminderNavigation {
    var unavailableMessage: String?
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private var pendingID: UUID?
    @ObservationIgnored private var resolve: ((UUID) throws -> ContentReveal)?
    @ObservationIgnored private var isWindowReady = false
    private let navigator: Navigator

    init(navigator: Navigator) { self.navigator = navigator }

    func receive(_ id: UUID) {
        pendingID = id
        openMainWindow?()
        drain()
    }

    func storeReady(resolve: @escaping (UUID) throws -> ContentReveal) {
        self.resolve = resolve
        drain()
    }

    func windowReady(_ value: Bool) {
        isWindowReady = value
        drain()
    }

    private func drain() {
        guard isWindowReady, let resolve, let id = pendingID else { return }
        pendingID = nil
        do {
            let request = try resolve(id)
            unavailableMessage = nil
            navigator.isSearchOpen = false
            navigator.isCommandPaletteOpen = false
            navigator.isShortcutSheetOpen = false
            navigator.reveal(request)
        } catch {
            unavailableMessage = "This reminder’s task is no longer available. It may have been deleted, moved out of this library, or not finished syncing."
        }
    }
}
