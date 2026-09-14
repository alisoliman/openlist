import SwiftData
import SwiftUI

struct MoveListSheet: View {
    let list: TaskList
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var lists: [TaskList]
    @State private var parentID: UUID?
    @State private var search = ""

    init(list: TaskList) {
        self.list = list
        _parentID = State(initialValue: list.parentListID)
    }

    var body: some View {
        let hierarchy = ListHierarchy(lists)
        VStack(alignment: .leading, spacing: 16) {
            Text("Move “\(list.displayTitle)”").font(.title2.bold())
            Text("Its child documents move with it. Sidebar pins and document contents stay attached to their existing lists.")
                .font(.callout).foregroundStyle(Theme.secondaryText)
            TextField("Find a parent list", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    destination("Top level", id: nil)
                    ForEach(lists.filter { hierarchy.canMove(list.id, under: $0.id) }
                        .filter { search.isEmpty || hierarchy.path(for: $0.id).localizedStandardContains(search) }
                        .sorted { hierarchy.path(for: $0.id).localizedStandardCompare(hierarchy.path(for: $1.id)) == .orderedAscending }) { parent in
                        destination(hierarchy.path(for: parent.id), id: parent.id)
                    }
                }
            }
            .frame(minHeight: 160, idealHeight: 240, maxHeight: 320)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Move") {
                    if env.store.moveList(list, under: parentID) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parentID == list.parentListID || !hierarchy.canMove(list.id, under: parentID))
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func destination(_ title: String, id: UUID?) -> some View {
        Button { parentID = id } label: {
            HStack {
                Image(systemName: parentID == id ? "checkmark.circle.fill" : "circle")
                Text(title).multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(parentID == id ? .isSelected : [])
    }
}
