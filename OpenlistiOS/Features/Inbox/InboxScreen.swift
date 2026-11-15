//
//  InboxScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// The Inbox (mockup 07): what's still to triage, newest first, each with how
/// long ago it came in, and Triage one by one. Ticking one dwells with Undo,
/// a date offers other days, and the rest of a row opens it. Select picks
/// several to file, date or clear at once. What's snoozed waits at the end,
/// each with the day it's back. Under them, the lists' tasks without a date
/// open triage's No date pass.
struct InboxScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @State private var isSelecting = false
    /// Inbox folds are local to this view, independent of document folds.
    @State private var expanded: Set<UUID> = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            page(now: env.now)
        }
    }

    private func page(now: Date) -> some View {
        let navigator = env.navigator
        let closing = env.actions.closing
        let captures = Self.captures(in: library, closing: closing, now: now)
        let snoozed = library.snoozedInbox(now: now)
        let outline = InboxTaskOutline(library: library)
        let rootIDs = Set((captures + snoozed).map(\.id))
        let toTriage = library.inboxQueue(triage: env.triage, closing: closing, now: now).count
        let kept = library.keptInbox(kept: library.kept(by: env.triage), now: now).count { !env.actions.isClosing($0.id) }
        // What No date would deal now; once all of it is set aside, what it
        // would deal again.
        let undatedLeft = library.undatedCount(triage: env.undatedTriage, closing: env.actions.closing, now: now)
        let undated = undatedLeft > 0 ? undatedLeft : library.undatedCount(kept: [], closing: env.actions.closing, now: now)
        let selectable = (captures + snoozed).filter { !$0.isCompleted }
        return OLScreen(identifier: PhoneRoute.inbox.screenIdentifier, scrolls: !captures.isEmpty || !snoozed.isEmpty) {
            OLTopBar {
                OLTitle("Inbox").padding(.leading, 10)
            } trailing: {
                HStack(spacing: 4) {
                    OLIconButton("checkmark.circle", label: "Select tasks", kind: .bare, iconSize: 22) { isSelecting = true }
                        .disabled(selectable.isEmpty)
                        .accessibilityHint(selectable.isEmpty ? "No open tasks to select" : "")
                        .accessibilityIdentifier("inbox.select")
                    OLIconButton("gearshape", label: "Settings", kind: .bare, iconSize: 22) { navigator.open(.settings) }
                        .accessibilityIdentifier("inbox.settings")
                }
            }
            .padding(.top, 4)
        } content: {
            Text(toTriage == 0 ? "All triaged" : "\(toTriage) to triage")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OL.muted)
                .contentTransition(.numericText())
                .padding(.top, 8)
            if captures.isEmpty && snoozed.isEmpty {
                if env.awaitsFirstImport(library) {
                    OLLoadingState("Getting your lists from iCloud…")
                        .frame(maxHeight: .infinity)
                } else {
                    OLEmptyState(symbol: "tray", title: "Inbox is empty",
                                 message: "What you capture lands here, to file or schedule later.",
                                 actionTitle: "Capture something") { navigator.open(.capture(CaptureRequest())) }
                        .frame(maxHeight: .infinity)
                }
            } else {
                if toTriage > 0 || kept == 0 {
                    Button("Triage one by one") { navigator.open(.triage(.inbox)) }
                        .buttonStyle(.ol(.primary, block: true))
                        .padding(.top, OLMetrics.headerGap)
                        .disabled(toTriage == 0 && captures.isEmpty)
                        .accessibilityIdentifier("inbox.triage")
                } else {
                    // Everything left was set aside this session: go over it again.
                    Button("Review what you kept") {
                        env.triage.reviewKept()
                        navigator.open(.triage(.inbox))
                    }
                    .buttonStyle(.ol(.neutral, block: true))
                    .padding(.top, OLMetrics.headerGap)
                    .accessibilityIdentifier("inbox.reviewKept")
                }
                if !captures.isEmpty {
                    rows(outline.rows(for: captures, rootIDs: rootIDs, expanded: expanded, closing: closing, now: now), now: now)
                        .padding(.top, OLMetrics.cardGap)
                }
                if !snoozed.isEmpty {
                    // Back by themselves on their day.
                    OLGroup("Snoozed") {
                        rows(outline.rows(for: snoozed, rootIDs: rootIDs, expanded: expanded, closing: closing,
                                          now: now, includesSnoozed: true), now: now)
                    }
                    .accessibilityIdentifier("inbox.snoozed")
                }
            }
            if undated > 0 {
                // Not the captures above, which have no date either.
                OLLinkRow("without a date in your lists", count: undated) {
                    // Everything left was set aside this session: go over it again.
                    if undatedLeft == 0 { env.undatedTriage.reviewKept() }
                    navigator.open(.triage(.undated))
                }
                .accessibilityHint("Triages them one by one")
                .accessibilityIdentifier("inbox.undated")
            }
        }
        .modifier(SelectMode(isSelecting: $isSelecting, listTitle: "Inbox", tasks: selectable))
    }

    private func rows(_ rows: [InboxTaskOutline.Row], now: Date) -> some View {
        OLCardRows(rows, lazy: true, depth: \.depth, shadow: .softCard) { row, separator in
            PhoneTaskDisclosureRow(taskTitle: row.task.displayTitle, separator: separator, progress: row.progress,
                                   isExpanded: row.isExpanded, identifier: "inbox.disclosure.\(row.id)",
                                   toggle: row.progress == nil ? nil : { toggle(row.id) }, labelFont: .caption) {
                InboxRow(task: row.task, depth: row.depth, now: now)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if !expanded.insert(id).inserted { expanded.remove(id) }
    }

    /// Open Inbox tasks and those dwelling, newest first, without what's
    /// snoozed past `now`'s day; a subtask goes with the open task above it,
    /// as its card does in triage.
    static func captures(in library: NextLibrary, closing: Set<UUID>, now: Date = .now) -> [Block] {
        library.tasks
            .filter { library.isInbox($0) && (!$0.isCompleted || closing.contains($0.id)) && !library.isUnderOpenTask($0) }
            .filter { !InboxPolicy.isSnoozed($0, now: now) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct InboxRow: View {
    let task: Block
    let depth: Int
    let now: Date
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let closing = env.actions.isClosing(task.id)
        let details = metadata(closing: closing)
        OLTaskRow(title: task.displayTitle,
                  state: PhoneTaskRow.check(for: task, closing: closing, now: now, calendar: env.settings.calendar),
                  depth: depth, subtitle: details.subtitle, emphasizesTitle: true, trailing: details.trailing,
                  onToggle: { env.actions.toggle(task) },
                  onOpen: { env.navigator.open(.taskDetail(task.id)) },
                  trailingControl: PhoneTaskRow.dueMenu(for: task, trailing: details.trailing, closing: closing))
            .contextMenu { PhoneTaskMenu(task: task) }
            .phoneTaskSwipe(task)
    }

    /// Passive capture and snooze details use the quieter subtitle style.
    private func metadata(closing: Bool) -> (subtitle: String?, trailing: OLTrailing?) {
        let calendar = env.settings.calendar
        if task.isCompleted {
            let completion = PhoneTaskRow.trailing(for: task, closing: closing, context: .list, now: now, calendar: calendar)
            return (nil, completion ?? .text("Done", tone: .done))
        }
        if let until = task.deferredUntil, InboxPolicy.isSnoozed(task, now: now, calendar: calendar) {
            let day = CompactText.day(until, now: now, calendar: calendar)
            return ("Snoozed until \(day)", nil)
        }
        if let due = CompactText.due(task.dueDate, includesTime: task.includesTime, now: now, calendar: calendar) {
            return (nil, .due(due))
        }
        return (CompactText.age(of: task.createdAt, now: now), nil)
    }
}
