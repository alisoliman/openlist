import SwiftUI

/// A sibling of the task's checkbox, title, and date controls, outside its swipe area.
struct PhoneTaskDisclosureRow<Content: View>: View {
    let taskTitle: String
    let separator: OLSeparator
    let progress: (done: Int, total: Int)?
    let isExpanded: Bool
    let identifier: String
    let toggle: (() -> Void)?
    var labelFont = OLFont.meta
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.olStyle) private var style

    var body: some View {
        Group {
            if let toggle {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    content
                    disclosure(toggle: toggle)
                        .padding(.trailing, 16)
                        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
                }
            } else {
                content
            }
        }
        .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
    }

    private func disclosure(toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(style.animation(OLStyle.fold), toggle)
        } label: {
            HStack(spacing: 5) {
                if let progress {
                    Text("\(progress.done)/\(progress.total)")
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .font(labelFont)
            .foregroundStyle(OL.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(OL.sunken, in: .capsule)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .accessibilityLabel("\(progress == nil ? "Contents" : "Subtasks") of \(taskTitle)")
        .accessibilityValue((isExpanded ? "Expanded" : "Collapsed")
            + (progress.map { ", \($0.done) of \($0.total) done" } ?? ""))
        .accessibilityHint(isExpanded ? "Collapse contents" : "Expand contents")
        .accessibilityIdentifier(identifier)
    }
}
