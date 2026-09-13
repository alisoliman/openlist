import SwiftUI

struct TaskSelectionScope: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @State private var scopeID = UUID()
    @State private var visibleIDs: [UUID] = []
    @State private var firstGroupByBlock: [UUID: UUID] = [:]

    func body(content: Content) -> some View {
        content
            .environment(\.rowSelectionContext, RowSelectionContext(scopeID: scopeID, visibleIDs: visibleIDs,
                firstGroupByBlock: firstGroupByBlock) {
                env.activeDocument = nil
            })
            .onPreferenceChange(VisibleSelectionIDsKey.self) { groups in
                let ids = groups.flatMap(\.blockIDs)
                visibleIDs = ids
                var first: [UUID: UUID] = [:]
                for group in groups {
                    for id in group.blockIDs where first[id] == nil { first[id] = group.id }
                }
                firstGroupByBlock = first
                env.navigator.reconcileSelection(scope: scopeID, visible: ids)
            }
            .onDisappear {
                if env.navigator.rowSelection.scopeID == scopeID { env.navigator.clearSelection() }
            }
    }
}
