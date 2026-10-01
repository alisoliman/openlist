import SwiftData
import SwiftUI

/// Tasks from any combination of lists share the same actions and detail
/// screen as their source lists. A completed row stays through its Undo dwell.
struct ListsTasksView: View {
    @Binding var selectedLists: Set<UUID>
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]

    var body: some View {
        let tasks = ListsTaskOverview.tasks(in: library, blocks: blocks, selectedLists: selectedLists)
        let openCount = tasks.count { !env.actions.isClosing($0.id) }
        OLGroup("\(openCount) open", topSpacing: 14) {
            Menu {
                Button {
                    selectedLists = []
                } label: {
                    Label("All lists", systemImage: selectedLists.isEmpty ? "checkmark" : "square.stack")
                }
                .accessibilityIdentifier("lists.filter.all")
                Divider()
                ForEach(library.lists) { list in
                    Button {
                        toggle(list.id)
                    } label: {
                        Label(library.hierarchy.path(for: list.id), systemImage: selectedLists.contains(list.id) ? "checkmark" : "circle")
                    }
                    .accessibilityIdentifier("lists.filter.\(list.id)")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(filterTitle)
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(OLFont.chipSmall)
                .foregroundStyle(OL.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(OL.sunken, in: .capsule)
            }
            .accessibilityLabel("Filter lists")
            .accessibilityValue(filterTitle)
            .accessibilityHint("Choose one or more lists")
            .accessibilityIdentifier("lists.filter")
        } content: {
            if tasks.isEmpty {
                OLEmptyState(symbol: "checkmark", tint: OL.successText, title: "All caught up",
                             message: selectedLists.isEmpty ? "No open tasks across your lists." : "No open tasks in these lists.",
                             actionTitle: selectedLists.isEmpty ? "Add a task" : "Show all lists") {
                    if selectedLists.isEmpty { env.navigator.open(.capture(CaptureRequest())) }
                    else { selectedLists = [] }
                }
                .padding(.top, 40)
            } else {
                OLCardRows(tasks) { task, separator in
                    PhoneTaskRow(task: task, context: .list, subtitle: ListsTaskOverview.source(of: task, in: library),
                                 separator: separator, showsCompletion: false)
                }
                .accessibilityIdentifier("lists.tasks")
            }
        }
        .onChange(of: library.lists.map(\.id), initial: true) { _, ids in
            selectedLists.formIntersection(ids)
        }
    }

    private var filterTitle: String {
        if selectedLists.count == 1, let id = selectedLists.first, library.list(id) != nil {
            return library.hierarchy.path(for: id)
        }
        return selectedLists.isEmpty ? "All lists" : "\(selectedLists.count) lists"
    }

    private func toggle(_ id: UUID) {
        if selectedLists.contains(id) { selectedLists.remove(id) }
        else { selectedLists.insert(id) }
    }
}
