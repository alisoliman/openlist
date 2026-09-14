//
//  openlistApp.swift
//  openlist
//
//  Created by Ali S on 04/09/2026.
//

import SwiftData
import SwiftUI

@main
struct openlistApp: App {
    @NSApplicationDelegateAdaptor(OpenlistApplicationDelegate.self) private var applicationDelegate
    private let container: ModelContainer?
    private let startupError: String?
    private let recoveryStorage: LibraryRestoreStorage
    @State private var env: AppEnvironment?

    init() {
        // Observe before opening the store so early CloudKit setup errors are
        // visible. Review/unsigned builds explicitly opt out, not into another DB.
        let reason = ICloudConfiguration.unavailableReason
        let sync = ICloudSyncMonitor(unavailableReason: reason)
        let storage = LibraryRestoreStorage(originalStoreURL: StoreLocation.storeURL, originalMediaURL: MediaStore.defaultDirectory)
        recoveryStorage = storage
        do {
            let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
            let startup = try storage.activatePending(currentSettings: .init(defaults: ReviewSession.defaults), using: reader)
            let loaded = try AppPersistence.openSelected(startup, storage: storage, iCloudUnavailableReason: reason)
            try storage.applySettings(startup, to: ReviewSession.defaults)
            try MediaStore.shared.selectStartupDirectory(startup.mediaURL)
            if storage.needsDerivedReset(startup, defaults: ReviewSession.defaults) {
                // No environment, foreground observer or other publisher exists
                // yet. Submit the reset before constructing any of those paths.
                NotificationService.shared.beginLibraryRestoreAtStartup()
            }
            container = loaded.container
            startupError = nil
            sync.state.unavailableReason = loaded.iCloudUnavailableReason
            if reason == nil { sync.startupWarning = loaded.iCloudUnavailableReason }

            // Store and @Query must share the main context: views pass their
            // models into mutations, so saving a second context loses edits.
            let context = loaded.container.mainContext
            let environment = AppEnvironment(context: context, sync: sync,
                libraryID: try? LibraryIdentity.read(at: startup.storeURL),
                libraryStorage: storage, libraryStartup: startup)
            _env = State(initialValue: environment)
            // Menu-bar-only launches must also migrate files and start sync.
            applicationDelegate.onDidLaunch = { [weak environment] in environment?.bootstrap() }
            applicationDelegate.hasPendingNotifications = { NotificationService.shared.reminders.isRefreshing }
            applicationDelegate.finishPendingNotifications = { await NotificationService.shared.reminders.drainForTermination() }
            applicationDelegate.persistPendingChanges = { [weak environment] in
                guard let environment else { return }
                do { try environment.store.persistChanges() }
                catch {
                    environment.store.persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
                    throw error
                }
            }
        } catch {
            container = nil
            _env = State(initialValue: nil)
            startupError = error.localizedDescription
        }
        applicationDelegate.sync = sync
    }

    var body: some Scene {
        Window("Openlist", id: WindowID.main) {
            if let env, let container {
                RootView()
                    .frame(minWidth: 640, minHeight: 420)
                    .environment(env)
                    .modelContainer(container)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
                    .environment(\.calendar, env.settings.calendar)
                    .environment(\.openURL, OpenURLAction { url in
                        guard LocalLink.isLocal(url) else { return .systemAction }
                        env.localLinks.receive(url)
                        return .handled
                    })
                    .task { env.bootstrap() }
                    .onOpenURL { url in
                        env.localLinks.receive(url)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            } else {
                ContentUnavailableView {
                    Label("Your saved data could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your existing database has not been replaced. Check available disk space and file permissions, then restart Openlist.\n\n\(startupError ?? "")")
                        .textSelection(.enabled)
                } actions: {
                    if (try? recoveryStorage.canCancelPending()) == true {
                        Button("Cancel pending restore and quit") {
                            do { try recoveryStorage.cancelPending(); ApplicationQuit.request() }
                            catch { showRecoveryError(error) }
                        }
                    }
                    if (try? recoveryStorage.selection())?.generation != nil {
                        Button("Return to Original and Quit") {
                            let alert = NSAlert()
                            alert.messageText = "Return to the original library?"
                            alert.informativeText = "Open Openlist again after it quits. The original library will be verified before opening; this restored library's files will be retained for recovery."
                            alert.addButton(withTitle: "Return to Original and Quit")
                            alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn {
                                do { try recoveryStorage.queueReturnToOriginal(); ApplicationQuit.request() }
                                catch { showRecoveryError(error) }
                            }
                        }
                    }
                    Button("Quit Openlist") { ApplicationQuit.request() }
                }
            }
        }
        .defaultSize(width: 1_180, height: 780)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            if let env { AppCommands(env: env) }
        }

        Window("Quick Add", id: WindowID.quickAdd) {
            if let env, let container {
                QuickAddWindowView()
                    .environment(env)
                    .modelContainer(container)
                    .environment(\.calendar, env.settings.calendar)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.top)
        .handlesExternalEvents(matching: [])

        Settings {
            if let env, let container {
                SettingsView()
                    .environment(env)
                    .modelContainer(container)
                    .environment(\.calendar, env.settings.calendar)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
            }
        }
        .handlesExternalEvents(matching: [])

        MenuBarExtra("Openlist", systemImage: "checkmark.circle", isInserted: menuBarBinding) {
            if let env, let container {
                MenuBarView()
                    .environment(env)
                    .modelContainer(container)
                    .environment(\.calendar, env.settings.calendar)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func showRecoveryError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Recovery could not be prepared"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { env?.settings.showsMenuBarExtra ?? false },
            set: { env?.settings.showsMenuBarExtra = $0 }
        )
    }
}

enum WindowID {
    static let main = "main"
    static let quickAdd = "quick-add"
}
