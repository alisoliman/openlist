import SwiftData
import SwiftUI

struct TrashScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var blocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var lists: [TaskList]
    @State private var entries: [TrashEntry] = []
    @State private var pendingErase: [UUID] = []
    @State private var showsEraseConfirmation = false

    var body: some View {
        ScreenScaffold(maxContentWidth: 840) {
            ScreenHeader(icon: "trash", title: "Trash") {
                if !entries.isEmpty {
                    Button("Empty Trash", role: .destructive) {
                        pendingErase = entries.map(\.id)
                        showsEraseConfirmation = true
                    }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                if entries.isEmpty {
                    EmptyStateView(icon: "trash", title: "Trash is empty",
                        message: "Deleted tasks and lists stay here until you remove them permanently.")
                } else {
                    Text("\(entries.count) items · Nothing is deleted automatically")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                        .help("\(ByteCountFormatter.string(fromByteCount: Int64(entries.reduce(0) { $0 + $1.byteCount }), countStyle: .file)) in retained files")
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(entry.title, systemImage: entry.isList ? "square.stack" : "doc.text")
                            .font(.headline)
                        if let metadata = entry.metadata {
                            Text("From \(metadata.formerLocation) · Deleted \(metadata.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Text("\(entry.isList ? "\(entry.listCount) documents · " : "")\(entry.blockCount) content blocks · \(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(env.store.trashRestoreDestination(entry))
                            .font(.callout)
                        HStack {
                            Button("Restore") { _ = env.store.restoreTrash(ids: [entry.id]); reload() }
                            Spacer()
                            Menu {
                                Button("Permanently Delete…", role: .destructive) {
                                    pendingErase = [entry.id]
                                    showsEraseConfirmation = true
                                }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 24, height: 24)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .accessibilityLabel("Trash actions for \(entry.title)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.secondaryText.opacity(0.06), in: .rect(cornerRadius: 12))
                }
            }
        }
        .confirmationDialog("Permanently delete \(pendingErase.count == 1 ? "this item" : "these items")?", isPresented: $showsEraseConfirmation, titleVisibility: .visible) {
            Button("Permanently Delete", role: .destructive) {
                _ = env.store.permanentlyEraseTrash(ids: pendingErase)
                reload()
            }
        } message: {
            Text("This removes the retained content and files that no other item uses. You cannot undo this action.")
        }
        .onAppear(perform: reload)
        .onChange(of: blocks.map(\.id) + lists.map(\.id)) { reload() }
    }

    private func reload() {
        do { entries = try env.store.trashEntries() }
        catch { env.store.trashError = "Trash could not be read. \(error.localizedDescription)" }
    }
}
