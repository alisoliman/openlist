//
//  OpenlistiOSApp.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// The iPhone app. It opens the same store, with the same schema and
/// CloudKit container, the Mac does, in the same order: the sync monitor
/// first, so early CloudKit setup errors are seen; then the container; then
/// the environment, which the delegate bootstraps at launch. A library that
/// can't open shows why and never an empty one in its place.
@main
struct OpenlistiOSApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer?
    private let startupError: String?
    @State private var env: PhoneEnvironment?

    init() {
        _ = OLSerif.isAvailable
        // Decided before the container exists: an unentitled process opens a
        // CloudKit-backed store without complaint, then crashes at CKContainer.
        let reason = ICloudConfiguration.unavailableReason
        let sync = ICloudSyncMonitor(unavailableReason: reason)
        do {
            let loaded = try AppPersistence.open(at: StoreLocation.storeURL, iCloudUnavailableReason: reason)
            container = loaded.container
            startupError = nil
            sync.state.unavailableReason = loaded.iCloudUnavailableReason
            if reason == nil { sync.startupWarning = loaded.iCloudUnavailableReason }
            // The Store and @Query share the main context: views hand their
            // models to mutations, so saving another context would lose edits.
            let environment = PhoneEnvironment(context: loaded.container.mainContext, sync: sync,
                                               libraryID: try? LibraryIdentity.read(at: StoreLocation.storeURL))
            _env = State(initialValue: environment)
            delegate.onDidLaunch = { [weak environment] in environment?.bootstrap() }
        } catch {
            container = nil
            startupError = error.localizedDescription
            _env = State(initialValue: nil)
        }
        delegate.sync = sync
    }

    var body: some Scene {
        WindowGroup {
            if let env, let container {
                PhoneRootView()
                    .environment(env)
                    .modelContainer(container)
                    .task { env.bootstrap() }
                    .onOpenURL { env.openLink($0) }
                    .environment(\.openURL, OpenURLAction { url in
                        // Links in notes open in the app when they're Openlist's.
                        env.openLink(url) ? .handled : .systemAction
                    })
            } else {
                LibraryFailureScreen(message: startupError ?? "")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: env?.sceneBecameActive()
            case .inactive: env?.sceneWillResignActive(toBackground: false)
            case .background: env?.sceneWillResignActive(toBackground: true)
            @unknown default: break
            }
        }
    }
}
