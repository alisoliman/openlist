import Foundation

/// Operation completion is not proof of global convergence. Report account
/// availability and individual transfers rather than a misleading "all synced".
nonisolated struct ICloudSyncState {
    enum Account: Equatable {
        case checking, available, signedOut, restricted, temporarilyUnavailable
        case failed(String)
    }

    enum Operation: Hashable, Sendable {
        case setup, download, upload
    }

    var unavailableReason: String?
    var account: Account = .checking
    private(set) var activeOperations: [UUID: Operation] = [:]
    private(set) var failures: [Operation: String] = [:]
    private(set) var lastUpload: Date?
    private(set) var lastDownload: Date?
    private var completedOperations: Set<UUID> = []

    var isEnabled: Bool { unavailableReason == nil }

    var title: String {
        guard isEnabled else { return "Local only" }
        switch account {
        case .checking: return "Checking iCloud"
        case .signedOut: return "Sign in to iCloud"
        case .restricted: return "iCloud is restricted"
        case .temporarilyUnavailable, .failed: return "iCloud unavailable"
        case .available:
            if !failures.isEmpty { return "iCloud needs attention" }
            if !activeOperations.isEmpty { return "Syncing with iCloud" }
            return "iCloud available"
        }
    }

    var detail: String {
        if let unavailableReason { return unavailableReason }
        switch account {
        case .checking:
            return "Checking this Mac's Apple Account. Your changes are saved locally."
        case .signedOut:
            return "Sign in to your Apple Account in System Settings and enable iCloud for Openlist. Local changes are kept while iCloud is unavailable."
        case .restricted:
            return "This Mac's account or parental controls restrict iCloud. Your data is still saved locally."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Local changes will sync automatically when it is available again."
        case let .failed(message):
            return "The iCloud account could not be checked. \(message)"
        case .available:
            if let error = failures[.setup] ?? failures[.upload] ?? failures[.download] {
                return "Local data is kept. iCloud will retry automatically. \(error)"
            }
            return "Lists, tasks, notes, labels, images and attachments sync privately through your Apple Account. Offline edits are saved on this Mac and transferred when iCloud is available."
        }
    }

    var hasProblem: Bool {
        guard isEnabled else { return false }
        switch account {
        case .checking: return false
        case .available: return !failures.isEmpty
        default: return true
        }
    }

    mutating func begin(_ operation: Operation, id: UUID) {
        guard isEnabled, !completedOperations.contains(id) else { return }
        activeOperations[id] = operation
    }

    mutating func finish(_ operation: Operation, id: UUID, at date: Date, error: String?) {
        guard isEnabled, completedOperations.insert(id).inserted else { return }
        activeOperations.removeValue(forKey: id)
        failures[operation] = error
        guard error == nil else { return }
        switch operation {
        case .setup: break
        case .upload: lastUpload = max(lastUpload ?? .distantPast, date)
        case .download: lastDownload = max(lastDownload ?? .distantPast, date)
        }
    }

    mutating func accountChanged() {
        account = .checking
        activeOperations = [:]
        completedOperations = []
        failures = [:]
        lastUpload = nil
        lastDownload = nil
    }
}
