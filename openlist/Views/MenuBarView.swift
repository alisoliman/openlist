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
                // which hid this whole section. The row count is capped instead.
                let shown = due.prefix(8)
                VStack(alignment: .leading, spacing: 1) {
                    section("Overdue", count: due.count(where: Self.isOverdue), rows: shown.filter(Self.isOverdue))
                    section("Due today", count: due.count { !Self.isOverdue($0) }, rows: shown.filter { !Self.isOverdue($0) })
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

    /// The design's "add" row, opening Quick Add.
    private var captureRow: some View {
        Button {
            dismiss()
            // Once the menu has gone, so the panel keeps the keyboard.
            DispatchQueue.main.async { QuickCapturePanel.shared.show() }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(env.workbench.style.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                    .frame(width: 15, height: 15)
                Text("New task…").font(.system(size: 13.5))
                Spacer(minLength: 8)
                Text("⇧⌥Space")
                    .font(NX.mono(10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.035), radius: 9,
                                        padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                                        foreground: NX.ink(0.55), hoverForeground: NX.ink))
        .padding(6)
        .help("Quick Add (⇧⌥Space)")
    }

    /// A small-caps heading and its rows; nothing when none are shown.
    @ViewBuilder
    private func section(_ title: String, count: Int, rows: [Block]) -> some View {
        if !rows.isEmpty {
            HStack(spacing: 6) {
                NXCapsTitle(text: title)
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NX.ink(0.3))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 4, trailing: 8))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(rows) { task in
                MenuBarTaskRow(block: task)
            }
        }
    }

    /// The widgets' empty state: a green tick over a serif line.
    private func nothingDue(_ style: NextStyle) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(NX.green, in: Circle())
                .accessibilityHidden(true)
            Text("Nothing due")
                .font(style.serifTitles ? NX.serif(21) : .system(size: 16, weight: .semibold))
                .foregroundStyle(NX.ink)
            Text("Overdue and today’s tasks show here")
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

    /// Overdue and due-today work, soonest first.
    private var dueTasks: [Block] {
        activeOpenTasks
            .filter(\.isDueOnOrBeforeToday)
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    /// Due on an earlier day, as the design's Overdue group; a time already
    /// past today stays under Today, its time chip red.
    private static func isOverdue(_ task: Block) -> Bool {
        task.dueDate.map { NXFormat.dayOffset($0) < 0 } ?? false
    }
}

/// A compact task row inside the menu bar popover, like the inspector's
/// subtask rows, with the due chip rows show.
struct MenuBarTaskRow: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
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

            if let chip = dueChip { NXChip(chip: chip) }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering ? NX.ink(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityAction(named: "Open task", open)
    }

    /// A time today, red once it has passed; otherwise the day, red when it
    /// was an earlier one.
    private var dueChip: NXChipModel? {
        guard let due = block.dueDate else { return nil }
        let offset = NXFormat.dayOffset(due)
        if block.includesTime, offset == 0 {
            return NXChipModel(id: "time", label: NXFormat.clock(due), icon: "bell.fill",
                               tone: due < .now ? .over : .accent, fill: true)
        }
        return NXChipModel(id: "due", label: NXFormat.dueLabel(due),
                           icon: offset < 0 ? "exclamationmark.circle.fill" : "calendar",
                           tone: offset < 0 ? .over : .accent, fill: offset < 0)
    }

    private func open() {
        openWindow(id: WindowID.main)
        NSApp.activate(ignoringOtherApps: true)
        if let listID = block.listID {
            env.navigator.go(to: .list(listID))
        }
        env.navigator.openTask(block.id)
    }
}
