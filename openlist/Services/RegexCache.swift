//
//  RegexCache.swift
//  openlist
//

import Foundation

/// Compiled-pattern cache.
///
/// Building `NSRegularExpression` is expensive enough that re-doing it per
/// keystroke shows up while typing, and both the date parser and the markdown
/// input rules run on every edit.
nonisolated final class RegexCache: @unchecked Sendable {
    private var storage: [String: NSRegularExpression] = [:]
    private let lock = NSLock()
    private let options: NSRegularExpression.Options

    init(options: NSRegularExpression.Options = []) {
        self.options = options
    }

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[pattern] { return cached }
        guard let created = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        storage[pattern] = created
        return created
    }
}
