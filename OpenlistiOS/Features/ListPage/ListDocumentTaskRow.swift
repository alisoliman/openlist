import SwiftUI

/// A separate disclosure leaves the shared task's checkbox, detail button,
/// context menu and horizontal gestures unchanged.
struct ListDocumentTaskRow: View {
    let row: BlockRow
    let separator: OLSeparator
    let canDisclose: Bool
    let progress: (done: Int, total: Int)?
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        PhoneTaskDisclosureRow(taskTitle: row.block.displayTitle, separator: separator, progress: progress,
                               isExpanded: !row.isCollapsed, identifier: "list.disclosure.\(row.id)",
                               toggle: canDisclose ? { env.store.toggleCollapse(row.block) } : nil, labelFont: .caption) {
            PhoneTaskRow(task: row.block, context: .list, depth: row.depth, emphasizesTitle: true, showsCompletion: false)
        }
    }
}
