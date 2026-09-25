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
        NX.registerFonts()
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
            // Quick Add floats in a panel of its own rather than a scene.
            QuickCapturePanel.shared.install(env: environment, container: loaded.container)
            // Menu-bar-only launches must also migrate files and start sync,
            // and take ⇧⌥Space, which needs no window.
            applicationDelegate.onDidLaunch = { [weak environment] in
                guard let environment else { return }
                environment.bootstrap()
                environment.libraryMaintenance?.startDailySnapshots(settings: environment.settings)
                QuickCapturePanel.shared.installHotKey(enabled: environment.settings.quickCaptureHotKeyEnabled)
            }
            applicationDelegate.hasPendingNotifications = { NotificationService.shared.reminders.isRefreshing }
            applicationDelegate.finishPendingNotifications = { await NotificationService.shared.reminders.drainForTermination() }
            applicationDelegate.persistPendingChanges = { [weak environment] in
                guard let environment else { return }
                // Rows still in the completion dwell show as done; write them first.
                environment.workbench.flushClosings()
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
                // Its motion is the Next style's, which follows Reduce Motion,
                // for keys as well as clicks.
                RootView()
                    .frame(minWidth: 640, minHeight: 420)
                    .environment(env)
                    .modelContainer(container)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
                    .environment(\.calendar, env.settings.calendar)
                    .environment(\.openURL, OpenURLAction { url in
                        // Widget links share the item-link scheme; openLink claims
                        // the ones this build can open before item-link handling.
                        guard LocalLink.isLocal(url) else { return .systemAction }
                        env.openLink(url)
                        return .handled
                    })
                    .task { env.bootstrap() }
                    .onOpenURL { url in
                        // Widget links bring Openlist forward as they need:
                        // Quick Add floats over the app in front. The rest are
                        // item links.
                        if !env.openLink(url) { NSApplication.shared.activate(ignoringOtherApps: true) }
                    }
                    .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            } else {
                LibraryFailureView(message: startupError ?? "", storage: recoveryStorage)
            }
        }
        .defaultSize(width: 1_180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            if let env { AppCommands(env: env) }
        }

        MenuBarExtra("Openlist", systemImage: "checkmark.circle", isInserted: menuBarBinding) {
            if let env, let container {
                // Its motion is the Next style's, which follows Reduce Motion.
                MenuBarView()
                    .environment(env)
                    .modelContainer(container)
                    .environment(\.calendar, env.settings.calendar)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
            }
        }
        .menuBarExtraStyle(.window)
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
}

/// The window when the library can't open: no shell, tray or notices, just
/// what happened and the ways out, on Next paper with the panels' title and
/// buttons.
private struct LibraryFailureView: View {
    let message: String
    let storage: LibraryRestoreStorage

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(NX.ink(0.4))
                .accessibilityHidden(true)
            NXPanelTitle("Your saved data could not be opened")
                .multilineTextAlignment(.center)
            Text("Your existing database has not been replaced. Check available disk space and file permissions, then restart Openlist.\n\n\(message)")
                .font(.system(size: 12.5))
                .foregroundStyle(NX.ink(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if (try? storage.canCancelPending()) == true {
                    Button("Cancel pending restore and quit") {
                        do { try storage.cancelPending(); ApplicationQuit.request() }
                        catch { showRecoveryError(error) }
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                }
                if (try? storage.selection())?.generation != nil {
                    Button("Return to original and quit") {
                        let alert = NSAlert()
                        alert.messageText = "Return to the original library?"
                        alert.informativeText = "Open Openlist again after it quits. The original library will be verified before opening; this restored library's files will be retained for recovery."
                        alert.addButton(withTitle: "Return to Original and Quit")
                        alert.addButton(withTitle: "Cancel")
                        if alert.runModal() == .alertFirstButtonReturn {
                            do { try storage.queueReturnToOriginal(); ApplicationQuit.request() }
                            catch { showRecoveryError(error) }
                        }
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                }
                Button("Quit Openlist") { ApplicationQuit.request() }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NX.paper)
    }

    private func showRecoveryError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Recovery could not be prepared"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
