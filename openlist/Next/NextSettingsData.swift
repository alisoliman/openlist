//
//  NextSettingsData.swift
//  openlist
//
//  Settings' iCloud details and Data group: export, library backup and
//  restore, activity history and reset.
//

import AppKit
import SwiftData
import SwiftUI

/// iCloud's account, transfers and problems, opened beneath the iCloud sync row.
struct NXICloudDetails: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let state = env.sync.state
        NXSettingDetail {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: state.isEnabled ? "icloud" : "icloud.slash")
                        .font(.system(size: 12, weight: .semibold))
                    Text(state.title).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(NX.ink)
                Text(state.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NX.ink(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                if state.lastUpload != nil || state.lastDownload != nil {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        if let date = state.lastUpload { transfer("Last upload", date) }
                        if let date = state.lastDownload { transfer("Last download", date) }
                    }
                }
                Button("Check iCloud status") {
                    env.store.prepareForSync()
                    env.sync.checkAccount()
                    NSApplication.shared.registerForRemoteNotifications()
                }
                .disabled(!state.isEnabled)
                if let error = env.store.syncPreparationError { problem("Files need attention", error) }
                if let error = env.sync.pushRegistrationError { problem("Background updates", error) }
                VStack(alignment: .leading, spacing: 6) {
                    NXCapsTitle(text: "How iCloud sync works")
                    Group {
                        Text("Use the same Apple Account on each Mac. Transfers run automatically on Apple's schedule, not immediately. Deletions sync too.")
                        Text("macOS can postpone background transfers on low battery, even while charging. Keep this Mac connected to power until its battery recovers if the initial sync is waiting.")
                        Text("Appearance, shortcuts and other app preferences stay on each Mac. Attachments are imported copies; reattach a file to sync edits made in another app.")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 10)
        }
        .task { env.sync.checkAccount() }
    }

    private func transfer(_ title: String, _ date: Date) -> some View {
        GridRow {
            Text(title).foregroundStyle(NX.ink(0.48))
            Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(NX.ink(0.7)).monospacedDigit()
        }
        .font(.system(size: 11.5, weight: .medium))
    }

    private func problem(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(NX.redText)
            Text(message).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct NXDataSettings: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var blocks: [Block]
    @Query(filter: TaskList.availablePredicate) private var lists: [TaskList]

    @State private var isConfirmingReset = false
    @State private var isConfirmingClearHistory = false

    var body: some View {
        let tasks = blocks.filter(\.isTask)
        let completed = tasks.filter(\.isCompleted).count
        NXSettingsGroup(title: "Data") {
            NXSettingRow(label: "Your data",
                         hint: "\(Self.count(lists.count, "list")) · \(Self.count(tasks.count, "task")), \(completed) completed · \(Self.count(blocks.count - tasks.count, "other block"))")
            NXSettingRow(label: "Export every list as Markdown",
                         hint: "Writes one Markdown file per list, with images and attachments in sibling assets folders. Existing files are kept.") {
                Button("Export…") { exportAll() }
            }
            if let library = env.libraryMaintenance {
                NXLibraryBackupRows(library: library)
            }
            NXSettingRow(label: "Activity history",
                         hint: "Clears all Updates, per-task Activity entries, and the completion heatmap on this Mac and, when connected, in iCloud. Tasks are kept.") {
                Button("Clear all activity history…", role: .destructive) {
                    isConfirmingClearHistory = true
                }
            }
            NXSettingRow(label: "Reset",
                         hint: "Permanently removes all lists, tasks, labels, and Trash. With iCloud enabled, this also deletes them on your other Macs. This cannot be undone.") {
                Button("Delete everything…", role: .destructive) {
                    isConfirmingReset = true
                }
            }
        }
        .alert("Clear all activity history?", isPresented: $isConfirmingClearHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { env.store.clearActivity() }
        } message: {
            Text("This removes all Updates and task Activity entries, including the completion heatmap and older events, on synced devices. Your tasks are kept.")
        }
        .alert("Delete everything?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { reset() }
        } message: {
            Text("All lists, tasks, notes and labels will be permanently removed. These deletions also sync to iCloud and your other Macs when connected.")
        }
    }

    /// "1 list", "3 lists".
    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var exported = 0
        do {
            for list in env.store.allLists(includeArchived: true) {
                let filename = MarkdownExportPackage.safeFilename(list.displayTitle) + ".md"
                let destination = MarkdownExportPackage.availableURL(in: folder, filename: filename)
                try MarkdownExporter.write(list: list, store: env.store, to: destination)
                exported += 1
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Export stopped"
            alert.informativeText = "\(exported) list(s) were exported. The remaining lists were not exported.\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func reset() {
        guard env.store.permanentlyResetLibrary() else { return }
        env.navigator.replace(with: .today)
    }
}

/// Backing up and restoring the whole library, and a restore in progress.
private struct NXLibraryBackupRows: View {
    @Bindable var library: LibraryMaintenance
    @State private var confirmsReturn = false

    var body: some View {
        let failure = library.error ?? library.pendingQuitError
        VStack(spacing: 0) {
            NXSettingRow(label: "Library backup and restore",
                         hint: library.isBusy ? "Working with library…"
                             : failure ?? library.status
                             ?? "A complete, unencrypted package of your library, history and files. Keep it somewhere private. Markdown export remains available for readable documents.",
                         hintColor: failure != nil && !library.isBusy ? NX.redText : NX.ink(0.48), selectable: true) {
                HStack(spacing: 6) {
                    Button("Back up library…") { Task { await library.exportBackup() } }
                    Button("Restore backup…") { Task { await library.chooseBackup() } }
                }
                .disabled(library.isBusy || library.hasPendingRestore)
            }
            if library.isLocalRestore {
                NXSettingRow(label: "Restored library · Local only",
                             hint: "This copy does not synchronize with iCloud. Your original library is retained separately.") {
                    Button("Return to original library…") { confirmsReturn = true }
                        .disabled(library.isBusy || library.hasPendingRestore)
                }
            }
            if library.hasPendingRestore {
                NXSettingRow(label: "Restore pending",
                             hint: "If quitting was stopped by a save error, save your changes and quit again, or cancel the pending restore.") {
                    HStack(spacing: 6) {
                        Button("Quit Openlist") { library.requestQuit() }
                        Button("Cancel pending restore") { library.cancelPending() }
                    }
                }
            }
            NXSettingRow(label: "Recovery files", hint: "Your original library and the recovery backups a restore keeps") {
                Button("Show recovery files") { library.showRecoveryFiles() }
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

/// What a backup holds, before it replaces the library shown on this Mac.
private struct LibraryRestorePreview: View {
    let preview: LibraryBackupPackage.Validated
    @Bindable var library: LibraryMaintenance

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore this backup?")
                    .font(NX.serif(26))
                    .padding(.vertical, NX.serifLeading(26, lineHeight: 1.1))
                    .foregroundStyle(NX.ink)
                Text("Format \(preview.manifest.version) · \(preview.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NX.ink(0.48))
            }
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
                row("Lists", "\(preview.snapshot.lists.filter { $0.trashID == nil && $0.mergedIntoID == nil }.count)")
                row("Archived lists", "\(preview.snapshot.lists.filter { $0.isArchived && $0.trashID == nil && $0.mergedIntoID == nil }.count)")
                row("Trash items", "\(preview.snapshot.lists.filter { $0.trashID == $0.id }.count + preview.snapshot.blocks.filter { $0.trashID == $0.id }.count)")
                row("Tasks (including Trash)", "\(preview.snapshot.taskCount)")
                row("Notes and other blocks", "\(preview.snapshot.blocks.count - preview.snapshot.taskCount)")
                row("Labels", "\(preview.snapshot.labels.count)")
                row("Activity entries", "\(preview.snapshot.activity.count)")
                row("Calendar records", "\(preview.snapshot.workSessions.count + preview.snapshot.completions.count + preview.snapshot.placements.count)")
                row("Files", "\(preview.manifest.assets.count) · \(ByteCountFormatter.string(fromByteCount: Int64(preview.mediaBytes), countStyle: .file))")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NX.inspector, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NX.ink(0.08), lineWidth: 0.5))
            Text("This replaces the library shown on this Mac with a local-only restored copy. It does not replace, reset or merge your iCloud library. Your original library and a recovery backup are kept.")
                .font(.system(size: 13))
                .foregroundStyle(NX.ink(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text("Open Openlist again after it quits to finish. Library preferences will be restored; permissions and connections stay on this Mac. Any open work session will be paused at its last recorded time.")
                .font(.system(size: 11.5))
                .foregroundStyle(NX.ink(0.48))
                .fixedSize(horizontal: false, vertical: true)
            if let error = library.error {
                Text(error).font(.system(size: 12)).foregroundStyle(NX.redText).textSelection(.enabled)
            }
            HStack(spacing: 6) {
                if library.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { library.preview = nil }
                    .buttonStyle(NXDialogButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Restore and Quit", role: .destructive) { Task { await library.confirmRestore() } }
                    .buttonStyle(NXDialogButtonStyle(kind: .destructive))
            }
            .disabled(library.isBusy)
        }
        .padding(24)
        .frame(width: 490)
        .background(NX.card)
        .interactiveDismissDisabled(library.isBusy)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(NX.ink(0.55))
            Text(value).foregroundStyle(NX.ink).monospacedDigit()
        }
        .font(.system(size: 12.5))
    }
}
