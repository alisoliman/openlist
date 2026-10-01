import SwiftUI

/// A separate disclosure leaves the shared task's checkbox, detail button,
/// context menu and horizontal gestures unchanged.
struct ListDocumentTaskRow: View {
    let row: BlockRow
    let separator: OLSeparator
    let canDisclose: Bool
    let progress: (done: Int, total: Int)?
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.olStyle) private var style

    var body: some View {
        if canDisclose {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))
            layout {
                task
                disclosure
                    .padding(.trailing, 16)
                    .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
            }
            .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
        } else {
            task.overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
        }
    }

    private var task: some View {
        PhoneTaskRow(task: row.block, context: .list, depth: row.depth, showsCompletion: false)
    }

    private var disclosure: some View {
        Button {
            withAnimation(style.animation(OLStyle.fold)) { env.store.toggleCollapse(row.block) }
        } label: {
            HStack(spacing: 5) {
                if let progress {
                    Text("\(progress.done)/\(progress.total)")
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(row.isCollapsed ? 0 : 90))
                    .accessibilityHidden(true)
            }
            .font(OLFont.meta)
            .foregroundStyle(OL.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(OL.sunken, in: .capsule)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .accessibilityLabel("\(progress == nil ? "Contents" : "Subtasks") of \(row.block.displayTitle)")
        .accessibilityValue((row.isCollapsed ? "Collapsed" : "Expanded")
            + (progress.map { ", \($0.done) of \($0.total) done" } ?? ""))
        .accessibilityHint(row.isCollapsed ? "Expand contents" : "Collapse contents")
        .accessibilityIdentifier("list.disclosure.\(row.id)")
    }
}
