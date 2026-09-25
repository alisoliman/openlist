//
//  MenuBarView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The menu bar popover: capture a task and glance at what is due.
struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted })
    private var openTasks: [Block]

    @Query(filter: TaskList.availablePredicate)
    private var activeLists: [TaskList]

    var body: some View {
        let style = env.workbench.style
        let due = dueTasks
        VStack(alignment: .leading, spacing: 0) {
            captureRow
            hairline

            if due.isEmpty {
                nothingDue(style)
            } else {
                // A plain stack, not a ScrollView: inside a MenuBarExtra window
                // a ScrollView has no intrinsic height and collapses to zero,
                // which hid this whole section. The row count is capped instead,
                // and shared so each group with tasks keeps its heading.
                let overdue = due.filter(Self.isOverdue)
                let today = due.filter { !Self.isOverdue($0) }
                let shown = Self.share(Self.rowLimit, overdue.count, today.count)
                VStack(alignment: .leading, spacing: 1) {
                    section("Overdue", tasks: overdue, showing: shown.first)
                    section("Due today", tasks: today, showing: shown.second)
                }
                .padding(6)
            }

            hairline
            footer
        }
        .frame(width: 320)
        .background(NX.card)
        .environment(\.nextStyle, style)
        .tint(style.accent)
    }

    /// The design's add row (`NXAddRow`), opening Quick Add.
    private var captureRow: some View {
        Button {
            // Before the popover goes, so the card can wait for it to let go of the keyboard.
            QuickCapturePanel.shared.showFromMenuBar(closing: NSApp.currentEvent?.window)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(NX.ink(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                    .frame(width: 15, height: 15)
                Text("New task…").font(.system(size: 13.5))
                // Only while it opens capture from any app: off, or held by
                // another app, it would promise a key that does nothing.
                if QuickCaptureHotKey.shared.isRegistered {
                    Text("⇧⌥Space")
                        .font(NX.mono(10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.035), radius: 9,
                                        padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                                        foreground: NX.ink(0.36), hoverForeground: NX.ink(0.55)))
        .padding(6)
        .help(QuickCaptureHotKey.shared.isRegistered ? "Quick Add (⇧⌥Space)" : "Quick Add")
    }

    /// A small-caps heading with the design's group count, the first
    /// `showing` rows, and the widgets' line for the rest; nothing without tasks.
    @ViewBuilder
    private func section(_ title: String, tasks: [Block], showing: Int) -> some View {
        if !tasks.isEmpty {
            HStack(spacing: 6) {
                NXCapsTitle(text: title)
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.38))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 4, trailing: 8))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(tasks.prefix(showing))) { task in
                MenuBarTaskRow(block: task)
            }
            if tasks.count > showing {
                // In line with the row titles, past the checkbox.
                Text("+\(tasks.count - showing) more")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.36))
                    .padding(EdgeInsets(top: 3, leading: 32, bottom: 4, trailing: 8))
            }
        }
    }

    /// The widgets' empty state, in the Today widget's words: a green tick
    /// over the serif "All clear".
    private func nothingDue(_ style: NextStyle) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(NX.green, in: Circle())
                .accessibilityHidden(true)
            Text("All clear")
                .font(style.serifTitles ? NX.serif(21) : .system(size: 16, weight: .semibold))
                .foregroundStyle(NX.ink)
            Text("Nothing due or overdue today")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NX.ink(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button("Open Openlist") {
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(NXHoverButtonStyle(radius: 6, padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
                                            foreground: NX.ink(0.6), hoverForeground: NX.ink))

            Spacer()

            Text("\(InboxPolicy(lists: activeLists).openCount(openTasks)) Inbox · \(activeOpenTasks.count) open")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NX.ink(0.45))
                .monospacedDigit()

            Button {
                ApplicationQuit.request()
            } label: {
                Image(systemName: "power").font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(NXHoverButtonStyle(radius: 6, padding: EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5),
                                            foreground: NX.ink(0.45), hoverForeground: NX.ink))
            .help("Quit")
            .accessibilityLabel("Quit Openlist")
        }
        .padding(6)
    }

    private var hairline: some View {
        Rectangle().fill(NX.ink(0.08)).frame(height: 0.5)
    }

    private var activeOpenTasks: [Block] {
        ActiveTaskPolicy(lists: activeLists).tasks(in: openTasks)
    }

    /// Rows the popover shows at most.
    private static let rowLimit = 8

    /// Half of `limit` for each group, a group with fewer tasks lending the
    /// rest to the other.
    private static func share(_ limit: Int, _ first: Int, _ second: Int) -> (first: Int, second: Int) {
        let shownFirst = min(first, limit - min(second, limit / 2))
        return (shownFirst, min(second, limit - shownFirst))
    }

    /// Overdue and due-today work, soonest first.
    private var dueTasks: [Block] {
        activeOpenTasks
            .filter(\.isDueOnOrBeforeToday)
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    /// Due on an earlier day, as the design's Overdue group; a time already
    /// past today stays under Today, as it does on the rows.
    private static func isOverdue(_ task: Block) -> Bool {
        task.dueDate.map { NXFormat.dayOffset($0) < 0 } ?? false
    }
}

/// A compact task row inside the menu bar popover, like the inspector's
/// subtask rows, with the time and due chips rows show and the rows' density.
struct MenuBarTaskRow: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @Environment(\.nextStyle) private var style
    @State private var hovering = false

    var body: some View {
        // SwiftUI may update this row after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { row }
    }

    private var row: some View {
        HStack(spacing: 9) {
            NXCheckbox(filled: block.isCompleted, closing: nil, priority: block.priority,
                       title: block.displayTitle, size: 15) {
                env.store.toggleCompletion(block)
            }

            Text(block.displayTitle)
                .font(.system(size: 13))
                .foregroundStyle(NX.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(dueChips) { NXChip(chip: $0) }
            }
        }
        .padding(.vertical, style.rowVerticalPadding)
        .padding(.horizontal, 8)
        .background(hovering ? NX.ink(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityAction(named: "Open task", open)
    }

    /// The rows' own time and due chips (`NXRowChips`): a time stays grey
    /// all day beside the accent Today, and only an earlier day reads as late.
    private var dueChips: [NXChipModel] {
        NXRowChips.chips(for: block, options: NXRowOptions(showList: false),
                         library: NextLibrary(lists: [], sections: [], labels: [], tasks: []), workbench: env.workbench)
            .filter { $0.id == "time" || $0.id == "due" }
    }

    /// As a search hit opens a task: on its list's screen, the Inbox's being
    /// triage, focused and in the inspector.
    private func open() {
        openWindow(id: WindowID.main)
        NSApp.activate(ignoringOtherApps: true)
        let workbench = env.workbench
        let id = block.id
        if let list = env.store.list(id: block.listID) { workbench.go(workbench.route(for: list)) }
        // Once the new screen is up, so it scrolls to the row.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { workbench.inspect(id) }
    }
}
