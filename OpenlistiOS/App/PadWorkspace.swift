import SwiftUI

/// Regular-width iPad windows keep the library next to the current page.
/// The detail uses the same route stacks as the compact dock.
struct PadWorkspace: View {
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    let trayBottom: CGFloat
    @Environment(PhoneEnvironment.self) private var env
    @State private var detailStackID = UUID()

    var body: some View {
        let environment = env
        let navigator = environment.navigator
        let tab = navigator.tab
        let stackID = detailStackID
        let currentStackID = $detailStackID
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            PadSidebar(detailStackID: $detailStackID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 258, max: 320)
        } detail: {
            PhoneTabStack(tab: tab, env: environment, acceptsPathChanges: { currentStackID.wrappedValue == stackID })
                .id(stackID)
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
    @Binding var detailStackID: UUID
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let navigator = env.navigator
        let findSelected = selection == .find("")
        return List(selection: Binding(get: { selection }, set: { if let route = $0 { navigator.show(route) } })) {
            Section {
                ForEach(PhoneTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .tag(root(for: tab))
                        .accessibilityIdentifier("sidebar.\(tab.rawValue)")
                }
                Button {
                    // A same-tab arrival replaces the existing stack. Its last
                    // binding write can otherwise clear the new Find route.
                    if navigator.tab == .lists { detailStackID = UUID() }
                    navigator.show(.find(""))
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .listRowBackground(RoundedRectangle(cornerRadius: 12)
                    .fill(findSelected ? OL.accentSoft : .clear)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3))
                .accessibilityAddTraits(findSelected ? .isSelected : [])
                .accessibilityIdentifier("sidebar.find")
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
            Label {
                Text(row.list.displayTitle)
                    .lineLimit(1)
            } icon: {
                OLListGlyph(icon: row.list.icon, accent: row.list.accent.color, size: 18)
                    .accessibilityHidden(true)
            }
            .padding(.leading, CGFloat(min(row.depth, 3)) * 12)
            .tag(PhoneRoute.list(row.id))
            .accessibilityIdentifier("sidebar.list.\(row.id.uuidString)")
        }
    }
}

extension EnvironmentValues {
    /// The split detail uses the system bar for the sidebar toggle and capture.
    @Entry var showsWorkspaceToolbar = false
}
