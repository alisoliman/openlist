//
//  TaskMetadataChips.swift
//  openlist
//

import SwiftData
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
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        MetadataFlowLayout {
            if let progress, progress.total > 0 {
                SubtaskProgressChip(done: progress.done, total: progress.total)
            }

            ForEach(labels.prefix(2)) { label in
                Button { onTapLabel(label) } label: {
                    Text(label.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .chipStyle(accent: label.accent.color)
                }
                .buttonStyle(.plain)
                .help("Label: \(label.name)")
                .accessibilityLabel("Edit label \(label.name)")
            }
            if labels.count > 2 {
                Button("+\(labels.count - 2)") { onTapLabel(labels[2]) }
                    .buttonStyle(.plain)
                    .chipStyle()
                    .accessibilityLabel("Edit \(labels.count - 2) more labels")
                    .help(labels.dropFirst(2).map(\.name).joined(separator: ", "))
            }

            if block.recurrence != nil {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .help(block.recurrence?.displayText ?? "Repeats")
                    .accessibilityLabel(block.recurrence?.displayText ?? "Repeats")
            }

            if block.reminderAt != nil {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Reminder set")
                    .accessibilityLabel("Reminder set")
            }

            if block.dueDate != nil {
                Button(action: onTapDue) {
                    DueDateChip(block: block)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit due date: \(Store.dueChipText(for: block))")
            }

            if block.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(ListAccent.amber.color)
                    .accessibilityLabel("Starred")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Today", "Tue", "12 Mar" — tinted red when overdue.
struct DueDateChip: View {
    let block: Block

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) subtasks complete")
    }
}

/// The circular checkbox in a task row's gutter.
struct TaskCheckbox: View {
    let isCompleted: Bool
    let accent: Color
    let priority: TaskPriority
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var completionPulse = 0
    @State private var isAcknowledging = false

    private var showsCheckmark: Bool { isCompleted || isAcknowledging }

    var body: some View {
        Button {
            if !isCompleted,
               Theme.Motion.allowsAnimation(reduceMotion: reduceMotion, eventType: NSApp.currentEvent?.type) {
                acknowledgeCompletion()
            }
            else { isAcknowledging = false }
            action()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(strokeColor, lineWidth: 1.5)
                    .frame(width: 15, height: 15)

                Circle()
                    .fill(accent)
                    .frame(width: 15, height: 15)
                    .opacity(showsCheckmark ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(showsCheckmark ? Color.white : accent.opacity(0.55))
                    .opacity(showsCheckmark || isHovering ? 1 : 0)
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel(isCompleted ? "Reopen task" : "Complete task")
        .accessibilityValue(isCompleted ? "Completed" : "Pending")
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion), value: showsCheckmark)
        .onChange(of: isCompleted) { _, completed in
            if !completed { isAcknowledging = false }
        }
        .task(id: completionPulse) {
            guard completionPulse > 0 else { return }
            // Also acknowledges a repeating occurrence, whose model remains
            // pending. This never delays the save or schedules a data mutation.
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            isAcknowledging = false
        }
        .help(isCompleted ? "Mark as not done (⌘D)" : "Mark as done (⌘D)")
    }

    private func acknowledgeCompletion() {
        isAcknowledging = true
        completionPulse &+= 1
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
