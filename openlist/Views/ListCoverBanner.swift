import AppKit
import SwiftUI

/// The same compact header is shared by Document and Tasks modes.
struct ListCoverBanner: View {
    let list: TaskList
    @State private var image: NSImage?

    var body: some View {
        Group {
            if list.coverFilename != nil, list.coverPresentation == .compact {
                if let image {
                    GeometryReader { geometry in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: 112)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 10))
                            .accessibilityLabel("List cover: \(list.coverMetadata?.displayName ?? list.displayTitle)")
                    }
                    .frame(height: 112)
                } else {
                    Label("Cover unavailable", systemImage: "photo")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .task(id: list.coverFilename) { loadImage() }
        .onChange(of: list.coverData) { _, _ in loadImage() }
    }

    private func loadImage() {
        image = list.coverFilename.flatMap { MediaStore.shared.image(named: $0, data: list.coverData) }
    }
}
