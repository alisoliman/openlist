import AppKit
import SwiftData
import SwiftUI

struct AttachmentRow: View {
    let attachment: Attachment
    let onDelete: () -> Void

    @Environment(AppEnvironment.self) private var env
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
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NX.ink(0.5))
                    .frame(width: 28, height: 28)
                    .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.4))
            }

            Spacer(minLength: 4)

            Button("Open attachment", systemImage: "arrow.up.forward.square", action: openAttachment)
                .labelStyle(.iconOnly)
                .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))
                .help("Open \(attachment.displayName)")

            Button("Remove attachment", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))
                .accessibilityLabel("Remove attachment \(attachment.displayName)")
                .help("Remove \(attachment.displayName)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovering ? NX.ink(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: openAttachment)
    }

    /// A file that won't open says so in the window's notice.
    private func openAttachment() {
        guard attachment.modelContext != nil, !attachment.isDeleted else { return }
        let failure = "“\(attachment.displayName)” could not be opened."
        do {
            if !NSWorkspace.shared.open(try attachment.fileURL()) { env.store.editorNotice = failure }
        } catch {
            env.store.editorNotice = "\(failure) \(error.localizedDescription)"
        }
    }
}
