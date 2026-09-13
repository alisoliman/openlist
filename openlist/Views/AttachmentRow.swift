import AppKit
import SwiftData
import SwiftUI

struct AttachmentRow: View {
    let attachment: Attachment
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        if attachment.modelContext != nil, !attachment.isDeleted {
            liveContent
        }
    }

    private var liveContent: some View {
        HStack(spacing: 8) {
            if attachment.isImage, let image = MediaStore.shared.image(named: attachment.filename, data: attachment.contentData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.chipFill)
                    )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName)
                    .font(Theme.Font.metadata)
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 4)

            Button("Open attachment", systemImage: "arrow.up.forward.square", action: openAttachment)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open \(attachment.displayName)")

            Button("Remove attachment", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove attachment \(attachment.displayName)")
                .help("Remove \(attachment.displayName)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Theme.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: openAttachment)
    }

    private func openAttachment() {
        guard attachment.modelContext != nil, !attachment.isDeleted else { return }
        do {
            guard NSWorkspace.shared.open(try attachment.fileURL()) else {
                throw CocoaError(.fileReadUnknown)
            }
        } catch {
            MarkdownExporter.presentError(error, operation: "Open attachment \(attachment.displayName)")
        }
    }
}
