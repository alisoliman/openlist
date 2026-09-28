//
//  InboxScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// The Inbox (mockup 07): what's still to triage, newest first, each with how
/// long ago it came in, and Triage one by one. Ticking one dwells with Undo;
/// the rest of a row opens it.
struct InboxScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            page(now: env.now)
        }
    }

    private func page(now: Date) -> some View {
        let navigator = env.navigator
        let captures = Self.captures(in: library, closing: env.actions.closing)
        let toTriage = library.inboxQueue(triage: env.triage, closing: env.actions.closing).count
        let kept = library.keptInbox(kept: env.triage.kept { id in library.tasks.first { $0.id == id }?.dueDate })
            .count { !env.actions.isClosing($0.id) }
        return OLScreen(identifier: PhoneRoute.inbox.screenIdentifier, scrolls: !captures.isEmpty) {
            OLTopBar { OLEyebrow(toTriage == 0 ? "All triaged" : "\(toTriage) to triage", color: OL.infoText) }
        } content: {
            OLHeader("Inbox")
            if captures.isEmpty {
                OLEmptyState(symbol: "tray", tint: OL.infoText, title: "Inbox is empty",
                             message: "What you capture lands here, to file or schedule later.",
                             actionTitle: "Capture something") { navigator.open(.capture(CaptureRequest())) }
                    .frame(maxHeight: .infinity)
            } else {
                if toTriage > 0 || kept == 0 {
                    Button("Triage one by one") { navigator.open(.triage) }
                        .buttonStyle(.ol(.primary, block: true))
                        .padding(.top, OLMetrics.headerGap)
                        .accessibilityIdentifier("inbox.triage")
                } else {
                    // Everything left was set aside this session: go over it again.
                    Button("Review what you kept") {
                        env.triage.reviewKept()
                        navigator.open(.triage)
                    }
                    .buttonStyle(.ol(.neutral, block: true))
                    .padding(.top, OLMetrics.headerGap)
                    .accessibilityIdentifier("inbox.reviewKept")
                }
                OLCardRows(captures) { task, separator in
                    InboxRow(task: task, separator: separator, now: now)
                }
                .padding(.top, OLMetrics.cardGap)
            }
        }
    }

    /// Open Inbox tasks and those dwelling, newest first; a subtask goes with
    /// the open task above it, as its card does in triage.
    static func captures(in library: NextLibrary, closing: Set<UUID>) -> [Block] {
        library.tasks
            .filter { library.isInbox($0) && (!$0.isCompleted || closing.contains($0.id)) && !library.isUnderOpenTask($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct InboxRow: View {
    let task: Block
    let separator: OLSeparator
    let now: Date
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let closing = env.actions.isClosing(task.id)
        OLTaskRow(title: task.displayTitle,
                  state: PhoneTaskRow.check(for: task, closing: closing, now: now, calendar: env.settings.calendar),
                  trailing: trailing, separator: separator,
                  onToggle: { env.actions.toggle(task) },
                  onOpen: { env.navigator.open(.taskDetail(task.id)) })
            .contextMenu { PhoneTaskMenu(task: task) }
    }

    /// Its age, or its date once it has one.
    private var trailing: OLTrailing {
        if let due = CompactText.due(task.dueDate, includesTime: task.includesTime, now: now, calendar: env.settings.calendar) {
            return .due(due)
        }
        return .text(CompactText.age(of: task.createdAt, now: now))
    }
}
