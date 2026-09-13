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
    @State private var env: AppEnvironment?

    init() {
        // Observe before opening the store so early CloudKit setup errors are
        // visible. Review/unsigned builds explicitly opt out, not into another DB.
        let reason = ICloudConfiguration.unavailableReason
        let sync = ICloudSyncMonitor(unavailableReason: reason)
        do {
            let loaded = try AppPersistence.open(at: StoreLocation.storeURL, iCloudUnavailableReason: reason)
            container = loaded.container
            startupError = nil
            sync.state.unavailableReason = loaded.iCloudUnavailableReason
            if reason == nil { sync.startupWarning = loaded.iCloudUnavailableReason }

            // Store and @Query must share the main context: views pass their
            // models into mutations, so saving a second context loses edits.
            let context = loaded.container.mainContext
            context.autosaveEnabled = true
            let environment = AppEnvironment(context: context, sync: sync)
            _env = State(initialValue: environment)
            // Menu-bar-only launches must also migrate files and start sync.
            applicationDelegate.onDidLaunch = { [weak environment] in environment?.bootstrap() }
        } catch {
            container = nil
            _env = State(initialValue: nil)
            startupError = error.localizedDescription
        }
        applicationDelegate.sync = sync
    }

    var body: some Scene {
        WindowGroup(id: WindowID.main) {
            if let env, let container {
                RootView()
                    .frame(minWidth: 640, minHeight: 420)
                    .environment(env)
                    .modelContainer(container)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
                    .environment(\.calendar, env.settings.calendar)
                    .task { env.bootstrap() }
            } else {
                ContentUnavailableView {
                    Label("Your saved data could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your existing database has not been replaced. Check available disk space and file permissions, then restart Openlist.\n\n\(startupError ?? "")")
                        .textSelection(.enabled)
                } actions: {
                    Button("Quit Openlist") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .defaultSize(width: 1_180, height: 780)
        .windowResizability(.contentMinSize)
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

        Settings {
            if let env, let container {
                SettingsView()
                    .environment(env)
                    .modelContainer(container)
                    .environment(\.calendar, env.settings.calendar)
                    .preferredColorScheme(env.settings.appearance.colorScheme)
            }
        }

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
