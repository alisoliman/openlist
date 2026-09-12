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
    private let container: ModelContainer
    @State private var env: AppEnvironment

    init() {
        let schema = Schema([
            TaskList.self,
            Block.self,
            SidebarSection.self,
            TaskLabel.self,
            Attachment.self,
            ActivityEvent.self,
        ])
        // Only the app opens this store. Widgets read a published snapshot,
        // and MCP calls use the app's own context.
        let configuration = ModelConfiguration(schema: schema, url: StoreLocation.storeURL)

        let container: ModelContainer
        var storageWarning: String?
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A schema the store cannot migrate would otherwise brick launch;
            // fall back to memory so the app still opens and can be reset.
            container = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            storageWarning = "Openlist could not open its saved data. This session is temporary: changes will be lost when you quit. Export any new work before closing. Your existing store has been left intact."
        }
        self.container = container

        // The store MUST share the container's main context. `@Query` hands
        // views objects registered there, and those objects are passed straight
        // into store mutations — with a second context the edits would land in
        // mainContext while `Store.save()` checked its own (always clean) one,
        // so nothing would ever persist or refresh the widget.
        let context = container.mainContext
        context.autosaveEnabled = true
        _env = State(initialValue: AppEnvironment(context: context))
        env.storageWarning = storageWarning
    }

    var body: some Scene {
        WindowGroup(id: WindowID.main) {
            RootView()
                .environment(env)
                .modelContainer(container)
                .preferredColorScheme(env.settings.appearance.colorScheme)
                // Publishing the calendar is what makes "Week starts on" reach
                // every date picker and formatter, not just the one grid that
                // asked for it explicitly.
                .environment(\.calendar, env.settings.calendar)
                .task { env.bootstrap() }
        }
        .defaultSize(width: 1_180, height: 780)
        .commands { AppCommands(env: env) }

        Window("Quick Add", id: WindowID.quickAdd) {
            QuickAddWindowView()
                .environment(env)
                .modelContainer(container)
                .environment(\.calendar, env.settings.calendar)
                .preferredColorScheme(env.settings.appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.top)

        Settings {
            SettingsView()
                .environment(env)
                .modelContainer(container)
                .environment(\.calendar, env.settings.calendar)
                .preferredColorScheme(env.settings.appearance.colorScheme)
        }

        MenuBarExtra("Openlist", systemImage: "checkmark.circle", isInserted: menuBarBinding) {
            MenuBarView()
                .environment(env)
                .modelContainer(container)
                .environment(\.calendar, env.settings.calendar)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { env.settings.showsMenuBarExtra },
            set: { env.settings.showsMenuBarExtra = $0 }
        )
    }
}

enum WindowID {
    static let main = "main"
    static let quickAdd = "quick-add"
}
