//
//  TaskMetadataChips.swift
//  openlist
//

import SwiftUI

/// The trailing metadata on a task row: due date, repeat, labels, subtask
/// progress and the star.
struct TaskMetadataChips: View {
    let block: Block
    let labels: [TaskLabel]
    let progress: (done: Int, total: Int)?
    var onTapDue: () -> Void = {}
    var onTapLabel: (TaskLabel) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 5) {
            if let progress, progress.total > 0 {
                SubtaskProgressChip(done: progress.done, total: progress.total)
            }

            ForEach(labels) { label in
                Button { onTapLabel(label) } label: {
                    Text(label.name)
                        .chipStyle(accent: label.accent.color)
                }
                .buttonStyle(.plain)
                .help("Label: \(label.name)")
            }

            if block.recurrence != nil {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .help(block.recurrence?.displayText ?? "Repeats")
            }

            if block.reminderAt != nil {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Reminder set")
            }

            if block.dueDate != nil {
                Button(action: onTapDue) {
                    DueDateChip(block: block)
                }
                .buttonStyle(.plain)
            }

            if block.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(ListAccent.amber.color)
            }
        }
        .fixedSize()
    }
}

/// "Today", "Tue", "12 Mar" — tinted red when overdue.
struct DueDateChip: View {
    let block: Block

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .semibold))
            Text(Store.dueChipText(for: block))
        }
        .chipStyle(accent: tint)
    }

    private var tint: Color? {
        if block.isCompleted { return nil }
        if block.isOverdue { return ListAccent.red.color }
        if block.isDueToday { return ListAccent.violet.color }
        return nil
    }

    private var symbolName: String {
        if block.isOverdue && !block.isCompleted { return "exclamationmark.circle.fill" }
        return "calendar"
    }
}

/// "2/5" progress pill shown on parents that have subtasks.
struct SubtaskProgressChip: View {
    let done: Int
    let total: Int

    private var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Theme.tertiaryText.opacity(0.4), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        fraction >= 1 ? ListAccent.green.color : Theme.accent,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 10, height: 10)

            Text("\(done)/\(total)")
        }
        .chipStyle()
        .help("\(done) of \(total) subtasks complete")
    }
}

/// The circular checkbox in a task row's gutter.
struct TaskCheckbox: View {
    let isCompleted: Bool
    let accent: Color
    let priority: TaskPriority
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(strokeColor, lineWidth: 1.5)
                    .frame(width: 15, height: 15)

                if isCompleted {
                    Circle()
                        .fill(accent)
                        .frame(width: 15, height: 15)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                } else if isHovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(accent.opacity(0.55))
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isCompleted)
        .help(isCompleted ? "Mark as not done (⌘D)" : "Mark as done (⌘D)")
    }

    private var strokeColor: Color {
        if isCompleted { return accent }
        switch priority {
        case .none: return Theme.tertiaryText.opacity(isHovering ? 0.9 : 0.55)
        case .low: return ListAccent.blue.color.opacity(0.8)
        case .medium: return ListAccent.orange.color.opacity(0.85)
        case .high: return ListAccent.red.color
        }
    }
}
