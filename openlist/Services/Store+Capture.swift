//
//  Store+Capture.swift
//  openlist
//

import Foundation
import SwiftData

/// Everything a freshly captured task should inherit from where it was typed.
struct CaptureDefaults {
    /// Whether typed phrases like "tomorrow at 6pm" should be read as a date.
    var parsesNaturalLanguage: Bool = true
    /// When the text carries no date of its own, start it due today.
    var dueTodayWhenUndated: Bool = false
    /// Labels applied on top of anything the text names with `#`.
    var labelIDs: [UUID] = []
    /// Insert at the top of the destination rather than the bottom.
    var prepend: Bool = true
}

/// A value-only capture: editing or dismissing it never creates model records.
struct TaskCaptureDraft {
    var text = ""
    var parsesNaturalLanguage = true
    var dueTodayWhenUndated = false
    var removesDate = false
    var removesRecurrence = false
    var removedLabels: Set<String> = []

    var preview: Preview {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = try? NSRegularExpression(pattern: "(?:^|\\s)#([\\p{L}0-9_-]+)")
        let content = NSMutableString(string: trimmed)
        let matches = pattern?.matches(in: trimmed, range: NSRange(location: 0, length: content.length)) ?? []
        let names = matches.map { content.substring(with: $0.range(at: 1)) }
        for match in matches.reversed() { content.deleteCharacters(in: match.range) }
        var title = String(content).trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = parsesNaturalLanguage ? DateParser.parse(title) : ParsedSchedule(cleanedText: title)
        let canParse = !parsed.isEmpty && !parsed.cleanedText.isEmpty
        if canParse { title = parsed.cleanedText }
        // Never turn a label-only capture into an untitled task.
        if title.isEmpty { return Preview(title: trimmed) }
        let due = canParse ? parsed.date : nil
        return Preview(
            title: title,
            date: removesDate ? nil : (due ?? (dueTodayWhenUndated ? Calendar.current.startOfDay(for: .now) : nil)),
            includesTime: !removesDate && canParse && parsed.includesTime,
            recurrence: removesRecurrence || !canParse ? nil : parsed.recurrence,
            labels: Array(Set(names)).filter { !removedLabels.contains($0) }.sorted()
        )
    }

    struct Preview {
        var title: String
        var date: Date?
        var includesTime = false
        var recurrence: Recurrence?
        var labels: [String] = []
    }
}

extension Store {
    /// Save a reviewed draft atomically. Failure rolls back only this capture;
    /// existing editor changes are flushed before starting the transaction.
    func saveCapture(_ preview: TaskCaptureDraft.Preview, destinationID: UUID?, selectedForDay: Date? = nil,
                     appendToRoot: Bool = false) throws -> Block {
        guard !preview.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureError.emptyTitle
        }
        try persistChanges()
        guard let destination = list(id: destinationID) ?? inboxList(), !destination.isEffectivelyArchived else {
            throw CaptureError.unavailableDestination
        }
        isSavingSuspended = true
        defer { isSavingSuspended = false }
        do {
            let document = DocumentContext(listID: destination.id)
            let block = appendToRoot ? appendBlock(kind: .task, to: document) : prependTask(to: document)
            setPlainText(block, preview.title)
            block.dueDate = preview.date
            block.selectedForDay = selectedForDay.map { Calendar.current.startOfDay(for: $0) }
            block.includesTime = preview.includesTime
            block.recurrence = preview.recurrence?.anchored(to: preview.date)
            block.labelIDs = preview.labels.compactMap { findOrCreateLabel(named: $0)?.id }
            log(.created, title: block.displayTitle, block: block, list: destination)
            try persistChanges()
            scheduleReminderIfNeeded(for: block)
            return block
        } catch {
            context.rollback()
            pendingActivity.removeAll()
            throw error
        }
    }

    enum CaptureError: LocalizedError {
        case emptyTitle, unavailableDestination
        var errorDescription: String? {
            switch self {
            case .emptyTitle: "Enter a task title before adding it."
            case .unavailableDestination: "That list is unavailable. Choose Inbox or another active list."
            }
        }
    }

    // MARK: - Capture

    /// Creates a task from free text, applying everything the text implies.
    ///
    /// Used by raw-text integrations and inline editor workflows. Interactive
    /// capture reviews a value-only preview first, then calls `saveCapture` so
    /// metadata the user removed is never silently parsed back into the task.
    @discardableResult
    func captureTask(
        text: String,
        in list: TaskList,
        defaults: CaptureDefaults = CaptureDefaults()
    ) -> Block {
        let document = DocumentContext(listID: list.id)
        let block = defaults.prepend
            ? prependTask(to: document)
            : appendBlock(kind: .task, to: document)

        block.labelIDs = resolvedLabelIDs(defaults.labelIDs)
        setPlainText(block, text.trimmingCharacters(in: .whitespacesAndNewlines))

        // Parsing runs against the stored text so it also strips the phrase.
        applyInlineMetadata(to: block, parsesNaturalLanguage: defaults.parsesNaturalLanguage)

        if block.dueDate == nil, defaults.dueTodayWhenUndated {
            block.dueDate = Calendar.current.startOfDay(for: .now)
        }

        log(.created, title: block.displayTitle, block: block, list: list)
        scheduleReminderIfNeeded(for: block)
        save()
        return block
    }

    /// Pulls dates, repeat rules and `#labels` out of a task's own text.
    ///
    /// Deciding that "call mum friday #home" means due-Friday, tagged-home is
    /// a domain rule, so it lives here rather than in a view. *When* to run it
    /// — on Return, on blur, on capture — stays with the caller.
    ///
    /// - Returns: `true` when the block was changed.
    @discardableResult
    func applyInlineMetadata(to block: Block, parsesNaturalLanguage: Bool) -> Bool {
        guard block.isTask, !block.text.isEmpty else { return false }

        // Edit the attributed content rather than the plain mirror, so that
        // stripping "tomorrow" out of "Call **mum** tomorrow" keeps the bold.
        let content = NSMutableAttributedString(attributedString: attributedContent(of: block))
        var didChange = false

        // #labels
        let labelMatches = Self.labelPattern?.matches(
            in: content.string,
            range: NSRange(location: 0, length: (content.string as NSString).length)
        ) ?? []
        if !labelMatches.isEmpty {
            let ns = content.string as NSString
            let names = labelMatches
                .filter { $0.numberOfRanges > 1 }
                .map { ns.substring(with: $0.range(at: 1)) }

            for name in names {
                if let label = findOrCreateLabel(named: name), !block.labelIDs.contains(label.id) {
                    block.labelIDs.append(label.id)
                }
            }
            // Right to left so earlier ranges stay valid.
            for match in labelMatches.reversed() {
                content.deleteCharacters(in: match.range)
            }
            didChange = !names.isEmpty
        }

        // Dates and repeat rules, re-parsed against whatever survived above.
        if parsesNaturalLanguage {
            let parsed = DateParser.parse(content.string)
            // A task that is *only* a date phrase would be left with no title,
            // so leave those alone.
            if !parsed.isEmpty, !parsed.cleanedText.isEmpty {
                if let date = parsed.date {
                    block.dueDate = date
                    block.includesTime = parsed.includesTime
                }
                if let recurrence = parsed.recurrence {
                    block.recurrence = recurrence.anchored(to: block.dueDate)
                }
                for range in parsed.consumedRanges.sorted(by: { $0.location > $1.location }) {
                    guard NSMaxRange(range) <= content.length else { continue }
                    content.deleteCharacters(in: range)
                }
                didChange = true
            }
        }

        guard didChange else { return false }

        collapseWhitespace(in: content)
        setContent(block, attributed: content)
        scheduleReminderIfNeeded(for: block)
        save()
        return true
    }

    /// Squeezes runs of spaces left behind by deletions, and trims the ends.
    private func collapseWhitespace(in content: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: "\\s{2,}") else { return }
        let matches = regex.matches(
            in: content.string,
            range: NSRange(location: 0, length: (content.string as NSString).length)
        )
        for match in matches.reversed() {
            content.replaceCharacters(in: match.range, with: " ")
        }

        let text = content.string as NSString
        var trailing = text.length
        while trailing > 0,
              let scalar = UnicodeScalar(text.character(at: trailing - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            trailing -= 1
        }
        if trailing < text.length {
            content.deleteCharacters(in: NSRange(location: trailing, length: text.length - trailing))
        }

        var leading = 0
        let updated = content.string as NSString
        while leading < updated.length,
              let scalar = UnicodeScalar(updated.character(at: leading)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            leading += 1
        }
        if leading > 0 {
            content.deleteCharacters(in: NSRange(location: 0, length: leading))
        }
    }

    private static let labelPattern = try? NSRegularExpression(pattern: "(?:^|\\s)#([\\p{L}0-9_-]+)")

    // MARK: - Command dispatch

    /// Runs a command that only needs a set of blocks.
    ///
    /// Both the outline and the cross-list screens issue the same task
    /// commands; keeping the bodies here means there is one definition of what
    /// ⌘D or ⌃T does, rather than one per screen.
    ///
    /// - Returns: `false` for commands that need an outline and so cannot be
    ///   served from a set of blocks alone.
    @discardableResult
    func perform(_ command: EditorCommand, on targets: [Block], undoManager: UndoManager? = nil) -> Bool {
        switch command {
        case .toggleCompletion:
            batch { for block in targets where block.isTask { toggleCompletion(block) } }

        case .setDueToday:
            batch { for block in targets where block.isTask { setDueToday(block) } }

        case .clearDueDate:
            batch { for block in targets where block.isTask { setDueDate(nil, for: block) } }

        case .clearLabels:
            batch { for block in targets where block.isTask { clearLabels(on: block) } }

        case .toggleStar:
            batch { for block in targets where block.isTask { toggleStar(block) } }

        case .addToInbox:
            _ = setInboxMembership(true, taskIDs: targets.filter(\.isTask).map(\.id), undoManager: undoManager)

        case .removeFromInbox:
            _ = setInboxMembership(false, taskIDs: targets.filter(\.isTask).map(\.id), undoManager: undoManager)

        case .deleteSelection:
            return trashBlocks(targets, undoManager: undoManager)

        case .newTask, .openDetails, .pickDueDate, .pickLabel,
             .indent, .outdent, .moveUp, .moveDown, .expandAll, .collapseAll:
            // Needs an editor, a picker, or a destination the store cannot pick.
            return false
        }
        return true
    }

    /// Runs `body` with saving suspended, then saves once.
    ///
    /// Bulk edits otherwise open one transaction — and fire one widget
    /// refresh — per block touched.
    func batch(_ body: () -> Void) {
        let wasSuspended = isSavingSuspended
        isSavingSuspended = true
        body()
        isSavingSuspended = wasSuspended
        save()
    }
}
