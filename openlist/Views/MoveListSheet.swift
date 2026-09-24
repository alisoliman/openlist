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
        let style = env.workbench.style
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                NXPanelTitle("Move “\(list.displayTitle)”")
                Text("Its nested lists, tasks, notes and files move with it. It stays pinned in the sidebar if it was.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(NX.ink(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            NXPanelField(icon: "magnifyingglass") {
                TextField("Find a parent list", text: $search)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    destination("Top level", id: nil)
                    ForEach(lists.filter { hierarchy.canMove(list.id, under: $0.id) }
                        .filter { search.isEmpty || hierarchy.path(for: $0.id).localizedStandardContains(search) }
                        .sorted { hierarchy.path(for: $0.id).localizedStandardCompare(hierarchy.path(for: $1.id)) == .orderedAscending }) { parent in
                        destination(hierarchy.path(for: parent.id), id: parent.id, list: parent)
                    }
                }
                .padding(5)
            }
            .frame(minHeight: 160, idealHeight: 240, maxHeight: 320)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button("Move") {
                    // One change with Undo in the tray.
                    if env.workbench.moveList(list, under: parentID) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(NXPanelButtonStyle(kind: .primary))
                .disabled(parentID == list.parentListID || !hierarchy.canMove(list.id, under: parentID))
            }
        }
        .padding(24)
        .frame(width: 460)
        .presentationBackground(NX.card)
        .tint(style.accent)
        // Presented from the window, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }

    private func destination(_ title: String, id: UUID?, list: TaskList? = nil) -> some View {
        Button { parentID = id } label: {
            HStack(spacing: 9) {
                Group {
                    if let list {
                        NXListGlyph(list: list, size: 13)
                    } else {
                        Image(systemName: "square.2.layers.3d")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(NX.ink(0.45))
                    }
                }
                .frame(width: 16)
                .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(NXPanelRowStyle(isOn: parentID == id))
        .accessibilityAddTraits(parentID == id ? .isSelected : [])
    }
}
