import SwiftUI

/// A pane supplies its complete displayed order; individual lazy rows never
/// register themselves as the source of range ordering.
struct RowSelectionContext {
    let scopeID: UUID
    let visibleIDs: [UUID]
    var firstGroupByBlock: [UUID: UUID] = [:]
    var activate: () -> Void = {}
}

private struct RowSelectionContextKey: EnvironmentKey {
    static let defaultValue: RowSelectionContext? = nil
}

extension EnvironmentValues {
    var rowSelectionContext: RowSelectionContext? {
        get { self[RowSelectionContextKey.self] }
        set { self[RowSelectionContextKey.self] = newValue }
    }
}

/// Each expanded group emits once from its eager container. SwiftUI reduces
/// siblings in structural order, including rows beyond the scroll viewport.
struct VisibleSelectionGroup: Equatable {
    let id: UUID
    let blockIDs: [UUID]
}

struct VisibleSelectionIDsKey: PreferenceKey {
    static let defaultValue: [VisibleSelectionGroup] = []
    static func reduce(value: inout [VisibleSelectionGroup], nextValue: () -> [VisibleSelectionGroup]) {
        value.append(contentsOf: nextValue())
    }
}

enum TaskSelectionScrollID: Hashable {
    case first(UUID)
    case repeated(group: UUID, block: UUID)
}
