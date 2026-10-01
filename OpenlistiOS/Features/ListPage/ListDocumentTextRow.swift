import SwiftUI

/// Readable document context stays between its tasks. Top-level headings
/// disclose their own section, using the shared document model's boundaries.
struct ListDocumentTextRow: View {
    let row: BlockRow
    let canDisclose: Bool
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.olStyle) private var style

    var body: some View {
        Group {
            if BlockTree.sectionLevel(of: row.block.kind) != nil {
                heading
                    .padding(.leading, CGFloat(row.depth) * 20)
            } else if row.block.kind == .divider {
                OLSeparatorLine(separator: .inset(16 + CGFloat(row.depth) * 20))
                    .padding(.vertical, 12)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if row.block.kind == .bullet { Text("•").accessibilityHidden(true) }
                    if row.block.kind == .numbered { Text("\(row.ordinal).").accessibilityHidden(true) }
                    if row.block.kind == .image {
                        Image(systemName: "photo").accessibilityHidden(true)
                    }
                    Text(row.block.kind == .image ? row.block.displayTitle : row.block.text)
                        .font(row.block.kind == .code ? OLFont.mono : OLFont.note)
                        .foregroundStyle(OL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .padding(.leading, CGFloat(row.depth) * 20)
                .accessibilityIdentifier("list.text.\(row.id)")
            }
        }
    }

    @ViewBuilder private var heading: some View {
        if canDisclose {
            Button {
                withAnimation(style.animation(OLStyle.fold)) { env.store.toggleCollapse(row.block) }
            } label: {
                HStack(spacing: 8) {
                    title
                    Image(systemName: "chevron.right")
                        .font(OLFont.meta)
                        .foregroundStyle(OL.muted)
                        .rotationEffect(.degrees(row.block.isCollapsed ? 0 : 90))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityLabel(row.block.displayTitle)
            .accessibilityValue(row.block.isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(row.block.isCollapsed ? "Expand section" : "Collapse section")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("list.disclosure.\(row.id)")
        } else {
            title
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var title: some View {
        Text(row.block.displayTitle)
            .font(OLFont.rowTitleStrong)
            .foregroundStyle(OL.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
