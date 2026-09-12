import Foundation
import Security
import SwiftData

nonisolated enum ICloudConfiguration {
    static let containerIdentifier = "iCloud.solimanali.openlist"

    static var unavailableReason: String? {
        if ReviewSession.identifier != nil {
            return "iCloud is disabled for this isolated review session."
        }
        guard let task = SecTaskCreateFromSelf(nil) else {
            return "This build's iCloud signing permissions could not be read."
        }
        func entitlement(_ key: String) -> CFTypeRef? {
            SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        }
        let containers = entitlement("com.apple.developer.icloud-container-identifiers") as? [String] ?? []
        let services = entitlement("com.apple.developer.icloud-services") as? [String] ?? []
        let environment = entitlement("com.apple.developer.icloud-container-environment") as? String
        let applicationID = entitlement("com.apple.application-identifier") as? String
        guard containers.contains(containerIdentifier), services.contains("CloudKit"),
              environment == "Development" || environment == "Production",
              let bundleID = Bundle.main.bundleIdentifier,
              applicationID?.hasSuffix(".\(bundleID)") == true else {
            return "This build is not provisioned for iCloud. Use a signed build with the Openlist iCloud container. Your data remains on this Mac."
        }
        return nil
    }
}

enum AppPersistence {
    static var modelTypes: [any PersistentModel.Type] {
        [TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self]
    }

    static var schema: Schema {
        Schema(modelTypes)
    }

    static func configuration(at url: URL, iCloudEnabled: Bool) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            url: url,
            cloudKitDatabase: iCloudEnabled ? .private(ICloudConfiguration.containerIdentifier) : .none
        )
    }

    struct LoadedStore {
        let container: ModelContainer
        let iCloudUnavailableReason: String?
    }

    /// Both attempts use the original store. Never replace unreadable data with
    /// an empty or in-memory database that merely looks like a successful launch.
    static func open(at url: URL, iCloudUnavailableReason: String?) throws -> LoadedStore {
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration(at: url, iCloudEnabled: iCloudUnavailableReason == nil)]
            )
            return LoadedStore(container: container, iCloudUnavailableReason: iCloudUnavailableReason)
        } catch {
            guard iCloudUnavailableReason == nil else { throw error }
            let cloudError = error
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration(at: url, iCloudEnabled: false)]
            )
            return LoadedStore(
                container: container,
                iCloudUnavailableReason: "iCloud could not start; local saving is still available. \(ICloudError.message(for: cloudError))"
            )
        }
    }
}
