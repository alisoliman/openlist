import SwiftUI

struct LibraryBackupControls: View {
    @Bindable var library: LibraryMaintenance
    @State private var confirmsReturn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Back up library…") { Task { await library.exportBackup() } }
                Button("Restore backup…") { Task { await library.chooseBackup() } }
            }
            .disabled(library.isBusy || library.hasPendingRestore)
            Text("A complete, unencrypted package of your library, history and files. Keep it somewhere private. Markdown export remains available for readable documents.")
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.secondaryText)
            if library.isLocalRestore {
                Label("Restored library · Local only", systemImage: "externaldrive")
                    .font(.headline)
                Text("This copy does not synchronize with iCloud. Your original library is retained separately.")
                    .font(Theme.Font.metadata)
                Button("Return to original library…") { confirmsReturn = true }
                    .disabled(library.isBusy || library.hasPendingRestore)
            }
            Button("Show recovery files") { library.showRecoveryFiles() }
            if library.isBusy { ProgressView("Working with library…").controlSize(.small) }
            if let status = library.status { Text(status).font(Theme.Font.metadata).textSelection(.enabled) }
            if let error = library.error ?? library.pendingQuitError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if library.hasPendingRestore {
                Text("If quitting was stopped by a save error, save your changes and quit again, or cancel the pending restore.")
                    .font(Theme.Font.metadata)
                HStack {
                    Button("Quit Openlist") { library.requestQuit() }
                    Button("Cancel pending restore") { library.cancelPending() }
                }
            }
        }
        .sheet(isPresented: Binding(get: { library.preview != nil }, set: { if !$0 { library.preview = nil } }),
               onDismiss: { library.previewDidDismiss() }) {
            if let preview = library.preview {
                LibraryRestorePreview(preview: preview, library: library)
            }
        }
        .alert("Return to the original library?", isPresented: $confirmsReturn) {
            Button("Cancel", role: .cancel) {}
            Button("Return to Original and Quit") { Task { await library.returnToOriginal() } }
        } message: {
            Text("Open Openlist again after it quits. The original library and its preferences will return, including its previous iCloud behavior. This restored copy will be retained separately; its changes are not merged into the original.")
        }
    }
}

private struct LibraryRestorePreview: View {
    let preview: LibraryBackupPackage.Validated
    @Bindable var library: LibraryMaintenance

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore this backup?").font(.title2.bold())
            Text("Format \(preview.manifest.version) · \(preview.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(Theme.secondaryText)
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
                row("Lists", "\(preview.snapshot.lists.filter { $0.mergedIntoID == nil }.count)")
                row("Archived lists", "\(preview.snapshot.lists.filter { $0.isArchived && $0.mergedIntoID == nil }.count)")
                row("Tasks", "\(preview.snapshot.taskCount)")
                row("Notes and other blocks", "\(preview.snapshot.blocks.count - preview.snapshot.taskCount)")
                row("Labels", "\(preview.snapshot.labels.count)")
                row("Activity entries", "\(preview.snapshot.activity.count)")
                row("Calendar records", "\(preview.snapshot.workSessions.count + preview.snapshot.completions.count + preview.snapshot.placements.count)")
                row("Files", "\(preview.manifest.assets.count) · \(ByteCountFormatter.string(fromByteCount: Int64(preview.mediaBytes), countStyle: .file))")
            }
            Text("This replaces the library shown on this Mac with a local-only restored copy. It does not replace, reset or merge your iCloud library. Your original library and a recovery backup are kept.")
            Text("Open Openlist again after it quits to finish. Library preferences will be restored; permissions and connections stay on this Mac. Any open work session will be paused at its last recorded time.")
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.secondaryText)
            if let error = library.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if library.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { library.preview = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Restore and Quit", role: .destructive) { Task { await library.confirmRestore() } }
            }
            .disabled(library.isBusy)
        }
        .padding(24)
        .frame(width: 490)
        .interactiveDismissDisabled(library.isBusy)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow { Text(title).foregroundStyle(Theme.secondaryText); Text(value) }
    }
}
