import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ListCoverMenu: View {
    let list: TaskList
    @Environment(AppEnvironment.self) private var env
    @State private var errorMessage = ""
    @State private var isShowingError = false

    var body: some View {
        Menu {
            Button(list.coverFilename == nil ? "Add cover from file…" : "Replace cover from file…", systemImage: "photo") {
                chooseImage()
            }
            if list.coverFilename != nil {
                Section("Cover display") {
                    ForEach(ListCoverPresentation.allCases) { presentation in
                        CheckmarkMenuItem(presentation.title, isSelected: list.coverPresentation == presentation) {
                            perform { try env.store.setListCoverPresentation(list, presentation: presentation) }
                        }
                    }
                }
                Divider()
                Button("Remove cover", systemImage: "trash", role: .destructive) {
                    perform { try env.store.removeListCover(list) }
                }
            }
        } label: {
            Label(list.coverFilename == nil ? "Add cover" : "Cover", systemImage: "photo")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose a local image for this list")
        .accessibilityLabel(list.coverFilename == nil ? "Add list cover" : "List cover options")
        .accessibilityValue(list.coverFilename == nil ? "No cover" : list.coverPresentation.title)
        .alert("Cover could not be changed", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = list.coverFilename == nil ? "Add list cover" : "Replace list cover"
        panel.prompt = "Choose image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image up to 20 MB and 40 megapixels. Openlist keeps its own copy."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        perform { try env.store.setListCover(list, from: source) }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() }
        catch { errorMessage = error.localizedDescription; isShowingError = true }
    }
}
