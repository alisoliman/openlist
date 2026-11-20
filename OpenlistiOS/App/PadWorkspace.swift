import SwiftUI

/// Regular-width iPad windows keep the library next to the current page.
/// The detail uses the same route stacks as the compact dock.
struct PadWorkspace: View {
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    let trayBottom: CGFloat
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let environment = env
        let navigator = environment.navigator
        let tab = navigator.tab
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            PadSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 258, max: 320)
        } detail: {
            PhoneTabStack(tab: tab, env: environment)
                .id(tab)
                .environment(\.showsWorkspaceToolbar, true)
                .environment(\.olScrollToTop, navigator.scrollToTopRequests(for: tab))
                .overlay(alignment: .bottom) {
                    TrayHost(announces: navigator.sheet == nil && navigator.cover == nil)
                        .frame(maxWidth: OLMetrics.paperWidth)
                        .padding(.bottom, trayBottom)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Each pushed page supplies these items to the detail navigation bar.
struct PadWorkspaceToolbar: ToolbarContent {
    let navigator: PhoneNavigator

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                var request = navigator.captureRequest
                request.listens = true
                navigator.open(.capture(request))
            } label: {
                Label("Say tasks", systemImage: "mic")
            }
            .accessibilityIdentifier("sidebar.voiceCapture")
            .disabled(!navigator.dockHiders.isEmpty)

            Button {
                navigator.open(.capture(navigator.captureRequest))
            } label: {
                Label("New task", systemImage: "plus")
            }
            .accessibilityIdentifier("sidebar.capture")
            .disabled(!navigator.dockHiders.isEmpty)
        }
    }
}

private struct PadSidebar: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        List {
            Section {
                ForEach(PhoneTab.allCases) { tab in
                    sidebarRow(route: root(for: tab), identifier: "sidebar.\(tab.rawValue)") {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                }
                sidebarRow(route: .find(""), identifier: "sidebar.find") {
                    Label("Find", systemImage: "magnifyingglass")
                }
                Button {
                    env.navigator.open(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("sidebar.settings")
            }

            ForEach(library.sections) { section in
                let lists = library.lists(in: section)
                if !lists.isEmpty {
                    Section(section.displayTitle) { listRows(lists) }
                }
            }
            if !library.unsectioned.isEmpty {
                Section("My Lists") { listRows(library.unsectioned) }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Openlist")
        .accessibilityIdentifier("ipad.sidebar")
    }

    private var selection: PhoneRoute? {
        let navigator = env.navigator
        for route in navigator.path(for: navigator.tab).reversed() {
            switch route {
            case .find: return .find("")
            case let .list(id):
                if let list = library.list(id), !list.isEffectivelyArchived { return route }
            default: break
            }
        }
        return root(for: navigator.tab)
    }

    private func root(for tab: PhoneTab) -> PhoneRoute {
        switch tab {
        case .today: .today
        case .inbox: .inbox
        case .lists: .lists
        case .work: .work
        }
    }

    private func listRows(_ lists: [TaskList]) -> some View {
        ForEach(library.outline(lists)) { row in
            sidebarRow(route: .list(row.id), identifier: "sidebar.list.\(row.id.uuidString)") {
                Label {
                    Text(row.list.displayTitle)
                        .lineLimit(1)
                } icon: {
                    OLListGlyph(icon: row.list.icon, accent: row.list.accent.color, size: 18)
                        .accessibilityHidden(true)
                }
                .padding(.leading, CGFloat(min(row.depth, 3)) * 12)
            }
        }
    }

    private func sidebarRow<Content: View>(route: PhoneRoute, identifier: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        let isSelected = selection == route
        return Button { env.navigator.show(route) } label: {
            content()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(isSelected ? OL.onAccent : OL.ink)
        }
        .buttonStyle(.plain)
        .listRowBackground(Capsule()
            .fill(isSelected ? OL.accent : .clear)
            .padding(.horizontal, 8)
            .padding(.vertical, 3))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

extension EnvironmentValues {
    /// The split detail uses the system bar for the sidebar toggle and capture.
    @Entry var showsWorkspaceToolbar = false
}
