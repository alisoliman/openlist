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

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" && !$0.isCompleted })
    private var openTasks: [Block]

    @Query(filter: #Predicate<TaskList> { !$0.isArchived && $0.mergedIntoID == nil })
    private var activeLists: [TaskList]


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            captureField
            Divider()

            if dueSoon.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(ListAccent.green.color)
                    Text("Nothing due")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                // A plain stack, not a ScrollView: inside a MenuBarExtra window
                // a ScrollView has no intrinsic height and collapses to zero,
                // which hid this whole section. The row count is already capped.
                VStack(spacing: 1) {
                    ForEach(dueSoon) { task in
                        MenuBarTaskRow(block: task)
                    }
                }
                .padding(6)
            }

            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var captureField: some View {
        Button {
            dismiss()
            openWindow(id: WindowID.quickAdd)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack {
                Label("New task…", systemImage: "plus.circle.fill")
                Spacer()
                Text("⇧⌥Space").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Open Openlist")
                    .font(Theme.Font.metadata)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)

            Spacer()

            Text("\(activeOpenTasks.count) open")
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.tertiaryText)

            Button {
                ApplicationQuit.request()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Overdue and due-today work, soonest first.
    private var activeOpenTasks: [Block] {
        ActiveTaskPolicy(lists: activeLists).tasks(in: openTasks)
    }

    private var dueSoon: [Block] {
        activeOpenTasks
            .filter(\.isDueOnOrBeforeToday)
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            .prefix(8)
            .map(\.self)
    }


}

/// A compact task row inside the menu bar popover.
struct MenuBarTaskRow: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            TaskCheckbox(
                isCompleted: block.isCompleted,
                accent: env.store.list(id: block.listID)?.accent.color ?? Theme.accent,
                priority: block.priority,
                action: { env.store.toggleCompletion(block) }
            )
            .accessibilityLabel("\(block.isCompleted ? "Reopen" : "Complete") \(block.displayTitle)")

            Text(block.displayTitle)
                .font(Theme.Font.body)
                .lineLimit(1)

            Spacer(minLength: 4)

            if block.dueDate != nil {
                DueDateChip(block: block)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Theme.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            openWindow(id: WindowID.main)
            NSApp.activate(ignoringOtherApps: true)
            if let listID = block.listID {
                env.navigator.go(to: .list(listID))
            }
            env.navigator.openTask(block.id)
        }
    }
}
