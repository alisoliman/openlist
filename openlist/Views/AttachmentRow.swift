import AppKit
import SwiftData
import SwiftUI

struct AttachmentRow: View {
    let attachment: Attachment
    let onDelete: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.displayScale) private var displayScale
    @State private var isHovering = false
    /// An image's thumbnail, decoded off the main thread for the file and
    /// size in `key`; nil when it couldn't be read.
    @State private var thumbnail: (key: String, image: NSImage?)?

    var body: some View {
        if attachment.modelContext != nil, !attachment.isDeleted {
            liveContent
        }
    }

    /// The thumbnail's longest side, in pixels: enough to fill its 28pt
    /// square from an image up to three times as wide as it's tall.
    private var thumbnailPixels: Int { Int((28 * 3 * displayScale).rounded(.up)) }

    private var thumbnailKey: String? {
        attachment.isImage ? "\(attachment.filename)@\(thumbnailPixels)" : nil
    }

    /// The thumbnail drawn: decoded already for this key, or kept from
    /// before, so hovering, or the task opening again, decodes nothing.
    private var thumbnailImage: NSImage? {
        guard attachment.isImage else { return nil }
        if let thumbnail, thumbnail.key == thumbnailKey { return thumbnail.image }
        return MediaStore.shared.cachedThumbnail(named: attachment.filename, maxPixelSize: thumbnailPixels)
    }

    private var liveContent: some View {
        HStack(spacing: 8) {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if attachment.isImage, thumbnail?.key != thumbnailKey {
                // The thumbnail's square while it's decoded.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NX.ink(0.06))
                    .frame(width: 28, height: 28)
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
                    .foregroundStyle(NX.textTertiary)
            }

            Spacer(minLength: 4)

            Button("Open attachment", systemImage: "arrow.up.forward.square", action: openAttachment)
                .labelStyle(.iconOnly)
                .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))

            Button("Remove attachment", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))
                .accessibilityLabel("Remove attachment \(attachment.displayName)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovering ? NX.ink(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: openAttachment)
        .task(id: thumbnailKey) { await loadThumbnail() }
    }

    /// Decodes an image's thumbnail at the size it's drawn, off the main thread.
    private func loadThumbnail() async {
        guard let key = thumbnailKey else { return }
        let filename = attachment.filename, pixels = thumbnailPixels
        if let image = MediaStore.shared.cachedThumbnail(named: filename, maxPixelSize: pixels) {
            thumbnail = (key, image)
            return
        }
        let data = attachment.contentData
        let image = await Task.detached(priority: .userInitiated) {
            MediaStore.shared.thumbnail(named: filename, data: data, maxPixelSize: pixels)
        }.value
        guard !Task.isCancelled else { return }
        thumbnail = (key, image)
    }

    /// A file that won't open says so in the window's notice.
    private func openAttachment() {
        guard attachment.modelContext != nil, !attachment.isDeleted else { return }
        let failure = "“\(attachment.displayName)” could not be opened."
        do {
            if !NSWorkspace.shared.open(try attachment.fileURL()) { env.store.actionError = failure }
        } catch {
            env.store.actionError = "\(failure) \(error.localizedDescription)"
        }
    }
}
