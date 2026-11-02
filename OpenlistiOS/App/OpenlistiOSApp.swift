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
/// can't open shows why, with Try Again, and never an empty one in its place.
@main
struct OpenlistiOSApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    private let sync: ICloudSyncMonitor
    /// Why iCloud is off before the store is opened, which each attempt to
    /// open it starts from.
    private let iCloudUnavailableReason: String?
    @State private var container: ModelContainer?
    @State private var startupError: String?
    @State private var failedRetries = 0
    @State private var env: PhoneEnvironment?

    init() {
        _ = OLSerif.isAvailable
        // Decided before the container exists: an unentitled process opens a
        // CloudKit-backed store without complaint, then crashes at CKContainer.
        let reason = ICloudConfiguration.unavailableReason
        let sync = ICloudSyncMonitor(unavailableReason: reason)
        self.sync = sync
        iCloudUnavailableReason = reason
        switch Self.open(sync: sync, iCloudUnavailableReason: reason) {
        case let .success(library):
            _container = State(initialValue: library.container)
            _env = State(initialValue: library.env)
            delegate.onDidLaunch = { [weak environment = library.env] in environment?.bootstrap() }
        case let .failure(error):
            _startupError = State(initialValue: error.localizedDescription)
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
                LibraryFailureScreen(message: startupError ?? "", failedRetries: failedRetries, retry: retry)
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

    /// Opens the store and the environment over it, the way launch does.
    private static func open(sync: ICloudSyncMonitor, iCloudUnavailableReason reason: String?)
        -> Result<(container: ModelContainer, env: PhoneEnvironment), Error> {
        do {
            let loaded = try AppPersistence.open(at: StoreLocation.storeURL, iCloudUnavailableReason: reason)
            sync.state.unavailableReason = loaded.iCloudUnavailableReason
            if reason == nil { sync.startupWarning = loaded.iCloudUnavailableReason }
            // The Store and @Query share the main context: views hand their
            // models to mutations, so saving another context would lose edits.
            let environment = PhoneEnvironment(context: loaded.container.mainContext, sync: sync,
                                               libraryID: try? LibraryIdentity.read(at: StoreLocation.storeURL))
            return .success((loaded.container, environment))
        } catch {
            return .failure(error)
        }
    }

    /// Opens the library again from its failure screen. Only a library that
    /// opens replaces the screen, which the root then bootstraps; otherwise
    /// the screen stays, saying why now.
    private func retry() {
        switch Self.open(sync: sync, iCloudUnavailableReason: iCloudUnavailableReason) {
        case let .success(library):
            container = library.container
            env = library.env
            startupError = nil
        case let .failure(error):
            startupError = error.localizedDescription
            failedRetries += 1
        }
    }
}
