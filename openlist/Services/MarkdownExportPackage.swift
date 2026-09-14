import Foundation

/// Writes a Markdown file and its portable sibling assets folder. Media is
/// staged first; a failed copy never replaces an existing Markdown document.
/// Existing asset folders and unrelated files are never overwritten.
enum MarkdownExportPackage {
    struct Asset {
        var key: String
        var source: URL
        var preferredFilename: String
    }

    static func write(
        to destination: URL,
        assets: [Asset],
        render: ([String: String]) -> String
    ) throws {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        var paths: [String: String] = [:]
        var publishedAssets: URL?
        let stage = parent.appendingPathComponent(".openlist-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: stage) }

        do {
            if !assets.isEmpty {
                try manager.createDirectory(at: stage, withIntermediateDirectories: false)
                let assetsDirectory = availableURL(
                    in: parent,
                    filename: safeFilename(destination.deletingPathExtension().lastPathComponent) + ".assets"
                )
                var used: Set<String> = []
                for asset in assets where paths[asset.key] == nil {
                    let base = safeFilename(asset.preferredFilename)
                    let name = availableFilename(base, used: &used)
                    try manager.copyItem(at: asset.source, to: stage.appendingPathComponent(name))
                    paths[asset.key] = assetsDirectory.lastPathComponent + "/" + name
                }
                // Moving the whole directory prevents partially copied assets
                // from appearing in a successful export.
                try manager.moveItem(at: stage, to: assetsDirectory)
                publishedAssets = assetsDirectory
            }
            try render(paths).write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            if let publishedAssets { try? manager.removeItem(at: publishedAssets) }
            throw error
        }
    }

    /// Publish an owned document tree as one atomic folder. Every file links
    /// within this folder; shared asset filenames are assigned only once.
    static func writeFolder(to destination: URL, assets: [Asset],
                            render: ([String: String]) -> [String: String]) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".openlist-export-\(UUID())", isDirectory: true)
        defer { try? manager.removeItem(at: stage) }
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        var paths: [String: String] = [:], used = Set<String>()
        if !assets.isEmpty {
            let folder = stage.appendingPathComponent("assets", isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: false)
            for asset in assets where paths[asset.key] == nil {
                let name = availableFilename(safeFilename(asset.preferredFilename), used: &used)
                try manager.copyItem(at: asset.source, to: folder.appendingPathComponent(name))
                paths[asset.key] = "assets/" + name
            }
        }
        for (name, markdown) in render(paths) {
            guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".md") else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try markdown.write(to: stage.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try manager.moveItem(at: stage, to: destination)
    }

    static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = cleaned.drop(while: { $0 == "." })
        guard !visible.isEmpty else { return "Untitled" }
        let filename = String(visible)
        let ext = (filename as NSString).pathExtension
        let suffix = !ext.isEmpty && ext.utf8.count <= 20 ? "." + ext : ""
        let stem = suffix.isEmpty ? filename : String(filename.dropLast(suffix.count))
        // Filesystem limits count bytes. Keep Unicode graphemes intact and
        // preserve the extension, with room for deduplication suffixes.
        var shortened = ""
        for character in stem {
            let next = String(character)
            guard shortened.utf8.count + next.utf8.count + suffix.utf8.count <= 180 else { break }
            shortened += next
        }
        return (shortened.isEmpty ? "Untitled" : shortened) + suffix
    }

    static func availableURL(in folder: URL, filename: String) -> URL {
        var used = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.map { $0.lowercased() } ?? [])
        return folder.appendingPathComponent(availableFilename(filename, used: &used))
    }

    private static func availableFilename(_ filename: String, used: inout Set<String>) -> String {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? filename : url.deletingPathExtension().lastPathComponent
        var candidate = filename
        var suffix = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(stem) \(suffix)" + (ext.isEmpty ? "" : ".\(ext)")
            suffix += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
