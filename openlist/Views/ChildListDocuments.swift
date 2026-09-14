import SwiftData
import SwiftUI

struct ChildListDocuments: View {
    let list: TaskList
    @Environment(AppEnvironment.self) private var env
    @Query private var lists: [TaskList]

    var body: some View {
        let hierarchy = ListHierarchy(lists)
        let children = hierarchy.children(of: list.id)
        if !children.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Child lists").font(.headline)
                    Spacer()
                    if hierarchy.activeIDs.contains(list.id) {
                        Button("New Child List", systemImage: "plus") { createChild() }
                            .buttonStyle(.borderless)
                    }
                }
                ForEach(children) { child in
                    Button {
                        env.navigator.go(to: .list(child.id))
                    } label: {
                        HStack(spacing: 10) {
                            Text(child.icon).accessibilityHidden(true)
                            Text(child.displayTitle).foregroundStyle(.primary)
                            if hierarchy.isArchived(child.id) {
                                Label("Archived", systemImage: "archivebox").font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                        }
                        .padding(10)
                        .background(Theme.chipFill, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open") { env.navigator.go(to: .list(child.id)) }
                        Button("Move List…") { env.listPendingMove = child }
                        Button(child.isArchived ? "Unarchive List" : "Archive List") {
                            env.store.setArchived(!child.isArchived, for: child)
                        }
                        Button("Delete List", role: .destructive) { env.requestDeleteList(child) }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func createChild() {
        if let child = env.store.createChildList(in: list) { env.navigator.go(to: .list(child.id)) }
    }
}
