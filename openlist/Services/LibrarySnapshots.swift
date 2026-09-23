import Foundation

/// The automatic daily copies of the library: one backup package a day in the
/// app's Application Support folder, keeping the newest fourteen. Only
/// packages named like a snapshot are listed or pruned; anything else in the
/// folder is left alone.
nonisolated struct LibrarySnapshots: Sendable {
    static let retained = 14
    private static let prefix = "Openlist Snapshot "
    let directory: URL

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        #if OPENLIST_DEV
        let defaultBase = base.appendingPathComponent("Openlist Dev", isDirectory: true)
        #else
        let defaultBase = base
        #endif
        return (ReviewSession.identifier.map { base.appendingPathComponent("Openlist-Review-\($0)", isDirectory: true) } ?? defaultBase)
            .appendingPathComponent("Openlist", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    struct Snapshot: Equatable, Sendable {
        var url: URL
        var createdAt: Date
    }

    /// Snapshots in the folder, newest first.
    func all() -> [Snapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            Self.date(fromName: name).map { Snapshot(url: directory.appendingPathComponent(name, isDirectory: true), createdAt: $0) }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Due when no snapshot was taken on `now`'s day. One dated after `now`,
    /// from a clock that was ahead, doesn't count as today's.
    func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let newest = all().first(where: { $0.createdAt <= now }) else { return true }
        return !calendar.isDate(newest.createdAt, inSameDayAs: now)
    }

    /// Where a snapshot taken at `date` is written.
    func destination(at date: Date) -> URL {
        directory.appendingPathComponent(Self.name(for: date), isDirectory: true)
    }

    /// Removes all but the newest `count` snapshots and returns what it removed.
    @discardableResult
    func prune(keeping count: Int = retained) throws -> [URL] {
        let stale = all().dropFirst(count).map(\.url)
        for url in stale { try FileManager.default.removeItem(at: url) }
        return stale
    }

    // MARK: Names

    /// "Openlist Snapshot 2026-09-24T083000Z.openlistbackup", in UTC so the
    /// names sort and parse the same in any time zone.
    static func name(for date: Date) -> String {
        "\(prefix)\(formatter().string(from: date)).\(LibraryBackupPackage.fileExtension)"
    }

    static func date(fromName name: String) -> Date? {
        let suffix = ".\(LibraryBackupPackage.fileExtension)"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        return formatter().date(from: String(name.dropFirst(prefix.count).dropLast(suffix.count)))
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        return formatter
    }
}
