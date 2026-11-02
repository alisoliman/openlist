//
//  Workbench+Export.swift
//  openlist
//

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// A Markdown export being written: how far it has got, for the window's
/// notice, or Settings' row for Export every list, and the Cancel there.
@Observable @MainActor
final class NXExport {
    /// The list being exported, as the tray names it; nil for every list.
    let list: String?
    /// What it counts: a list's files, or every list's lists.
    let unit: String
    let total: Int
    private(set) var done = 0
    /// Set once it has run long enough to be worth showing, so a quick
    /// export never flashes a notice.
    fileprivate(set) var isShown = false
    @ObservationIgnored fileprivate var stop: () -> Void = {}

    fileprivate init(list: String?, unit: String, total: Int) {
        self.list = list
        self.unit = unit
        self.total = total
    }

    /// Settings' Export every list, which its own row shows.
    var isEveryList: Bool { list == nil }

    /// "Exporting “Trip” · 3 of 12 files…", or "Exporting 3 of 12 lists…":
    /// the one being written, of them all.
    var progress: String {
        let count = "\(min(done + 1, total)) of \(total) \(total == 1 ? unit : unit + "s")"
        guard let list else { return "Exporting \(count)…" }
        return total > 0 ? "Exporting \(list) · \(count)…" : "Exporting \(list)…"
    }

    func cancel() { stop() }

    fileprivate func advance(to count: Int) { done = max(done, count) }
}

extension Workbench {
    /// A list's Export as Markdown…, from its "…" menu, the sidebar, Lists or
    /// ⇧⌘E: the panel, then the export, its files copied off the main thread,
    /// counted in the window's notice with Cancel once it takes a moment.
    /// Once it's written, a line in the tray says so, as Copy as Markdown
    /// beside it does there; a failure says why in the window's notice. A
    /// native extra: the design has no export.
    func exportMarkdown(_ list: TaskList) {
        guard !refusesWhileExporting() else { return }
        Task {
            guard let destination = await chooseExportDestination(for: list), !refusesWhileExporting() else { return }
            let failure = "“\(list.displayTitle)” could not be exported."
            let prepared: MarkdownExporter.Prepared
            do { prepared = try MarkdownExporter.prepare(list: list, store: store, to: destination) } catch {
                store.actionError = "\(failure) \(error.localizedDescription)"
                return
            }
            let progress = NXExport(list: NXFormat.quoted(list.displayTitle), unit: "file", total: prepared.fileCount)
            switch await run(progress, { try await Self.publish(prepared, counting: progress) }) {
            case .success:
                showTray("Exported \(NXFormat.quoted(list.displayTitle)) as Markdown", icon: "square.and.arrow.up")
            case .failure(is CancellationError):
                showTray("Stopped exporting \(NXFormat.quoted(list.displayTitle))", icon: "square.and.arrow.up")
            case let .failure(error):
                store.actionError = "\(failure) \(error.localizedDescription)"
            }
        }
    }

    /// Settings' Export every list as Markdown: each top-level list in the
    /// folder chosen, as its own Export writes it, its files copied off the
    /// main thread, with Settings' row counting the lists, and Cancel, once
    /// it takes a moment. Said in the tray once done, as a list's own export
    /// is; what stopped it part way stays in the window's notice.
    func exportEveryList() {
        guard !refusesWhileExporting() else { return }
        Task {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export"
            guard await panel.nxRun() == .OK, let folder = panel.url, !refusesWhileExporting() else { return }
            let lists = MarkdownExporter.everyList(store: store)
            let progress = NXExport(list: nil, unit: "list", total: lists.reduce(0) { $0 + $1.documents })
            let result = await run(progress) {
                for (list, documents) in lists {
                    try Task.checkCancellation()
                    let destination = MarkdownExporter.destination(for: list, in: folder, documents: documents)
                    let prepared = try MarkdownExporter.prepare(list: list, store: self.store, to: destination)
                    try await Self.publish(prepared, counting: nil)
                    progress.advance(to: progress.done + documents)
                }
            }
            let exported = Self.count(progress.done, "list")
            switch result {
            case .success:
                showTray("Exported \(exported) as Markdown", icon: "square.and.arrow.up")
            case .failure(is CancellationError):
                showTray("Stopped exporting · \(progress.done) of \(Self.count(progress.total, "list")) exported", icon: "square.and.arrow.up")
            case let .failure(error):
                // What needs dealing with stays in the window's notice.
                let done = progress.done == 0 ? "No lists were exported."
                    : "\(exported) \(progress.done == 1 ? "was" : "were") exported; the remaining lists were not."
                store.actionError = "Export stopped. \(done) \(error.localizedDescription)"
            }
        }
    }

    /// One export at a time: another asked for meanwhile is refused, saying why.
    private func refusesWhileExporting() -> Bool {
        guard export != nil else { return false }
        store.refuse("Another export is under way. Wait for it, or cancel it, then export again.")
        return true
    }

    /// Runs `operation` as the export under way: in the window's notice, or
    /// Settings' row, from a moment in, with Cancel, and gone once it's
    /// over, however it ended.
    private func run(_ progress: NXExport, _ operation: @escaping @MainActor () async throws -> Void) async -> Result<Void, Error> {
        export = progress
        let work = Task { () -> Result<Void, Error> in
            do { try await operation(); return .success(()) } catch { return .failure(error) }
        }
        progress.stop = { work.cancel() }
        let reveal = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { progress.isShown = true }
        }
        let result = await work.value
        reveal.cancel()
        if export === progress { export = nil }
        return result
    }

    /// Writes `prepared` off the main thread, counting each file copied in
    /// `progress`, until it's written or cancelled.
    private static func publish(_ prepared: MarkdownExporter.Prepared, counting progress: NXExport?) async throws {
        let writing = Task.detached(priority: .userInitiated) {
            try prepared.publish { copied in
                try Task.checkCancellation()
                if let progress { Task { @MainActor in progress.advance(to: copied) } }
            }
        }
        try await withTaskCancellationHandler { try await writing.value } onCancel: { writing.cancel() }
    }

    /// Asks where `list`'s export goes: a folder, which its Markdown and
    /// files go in side by side, when it has files or nested lists, or else
    /// the Markdown file itself.
    private func chooseExportDestination(for list: TaskList) async -> URL? {
        let documents = store.listHierarchy().subtree(of: list.id)
        let blocks = documents.flatMap { store.blocks(inList: $0.id) }
        let hasMedia = list.coverFilename != nil || blocks.contains { $0.mediaFilename != nil || !store.attachments(for: $0.id).isEmpty }
        let filename = "\(MarkdownExportPackage.safeFilename(list.displayTitle)).md"
        if hasMedia || documents.count > 1 {
            // A save-panel grant covers the selected file, not an arbitrary
            // sibling assets folder. Select its parent to grant the sandbox
            // access to both parts of this portable export.
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.title = "Export \(list.displayTitle)"
            panel.prompt = "Export"
            panel.message = documents.count > 1
                ? "Choose where to export a folder holding one Markdown file for this list and one for each list nested in it, linked together, with their shared assets. Existing files are kept."
                : "Choose a folder for \(filename) and its images and attachments. Keep the Markdown file and assets folder together when sharing. Existing files are kept."
            guard await panel.nxRun() == .OK, let folder = panel.url else { return nil }
            return MarkdownExporter.destination(for: list, in: folder, documents: documents.count)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.title = "Export \(list.displayTitle)"
        guard await panel.nxRun() == .OK else { return nil }
        return panel.url
    }

    /// "1 list", "3 lists".
    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
