import SwiftUI

struct TemplateCopySheet: View {
    let request: TemplateCopyRequest
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var keepsRecurrence = false
    @State private var error: String?

    private var sources: [Block] {
        switch request.source {
        case let .task(id):
            guard let task = env.store.block(id: id) else { return [] }
            return (try? env.store.copySources(for: task)) ?? []
        // A list's copy holds its nested lists' tasks too.
        case let .list(id): return env.store.listHierarchy().subtree(of: id).flatMap { env.store.blocks(inList: $0.id) }
        }
    }

    /// What the copy holds, in the words the task's and list's own sheets use.
    private var contents: String {
        switch request.source {
        case .task: "A fresh copy with its subtasks, notes and files."
        case .list: "A fresh copy with its nested lists, tasks, notes and files."
        }
    }

    private var sourceTitle: String {
        switch request.source {
        case let .task(id): env.store.block(id: id)?.displayTitle ?? "Unavailable task"
        case let .list(id): env.store.list(id: id)?.displayTitle ?? "Unavailable list"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                NXPanelTitle("Use as template")
                Text(sourceTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .lineLimit(3)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(contents) Tasks start open, with no due dates, reminders or planned time.")
                    .foregroundStyle(NX.ink(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Labels, priority, stars and formatting are kept. The original stays unchanged.")
                    .foregroundStyle(NX.ink(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .lineSpacing(2)
            if sources.contains(where: { $0.recurrence != nil }) {
                let hint = "Repeats start with zero completions and no end date. Choose a new due date after copying."
                // A settings row: the design's 500 13px label and 11.5px hint beside its switch.
                // The switch speaks for the row. Its words toggle it too, from beside
                // the switch rather than over it, so one click never toggles twice.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep repeating rules")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NX.ink)
                        Text(hint)
                            .font(.system(size: 11.5))
                            .foregroundStyle(NX.ink(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.leading, 14)
                    .contentShape(Rectangle())
                    .onTapGesture { keepsRecurrence.toggle() }
                    .accessibilityHidden(true)
                    NXToggle(isOn: keepsRecurrence, label: "Keep repeating rules") { keepsRecurrence.toggle() }
                        .accessibilityHint(hint)
                        .accessibilityIdentifier("template-keep-recurrence")
                        .padding(.trailing, 14)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
            }
            if let error {
                NXSheetError(error)
                    .accessibilityIdentifier("template-copy-error")
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button("Create copy", action: createCopy)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
                    .accessibilityIdentifier("template-create-copy")
            }
        }
        .padding(24)
        .frame(width: 430)
        .presentationBackground(NX.card)
        .tint(env.workbench.style.accent)
        // Presented from the window, outside the Next shell's style.
        .environment(\.nextStyle, env.workbench.style)
    }

    private func createCopy() {
        do {
            // One change with Undo in the tray: a task's copy opens in the
            // inspector, a list's on its page.
            switch request.source {
            case let .task(id):
                try env.workbench.copyAsTemplate(id, keepingRecurrence: keepsRecurrence)
            case let .list(id):
                try env.workbench.copyListAsTemplate(id, keepingRecurrence: keepsRecurrence)
            }
            dismiss()
        } catch {
            self.error = "The copy was not created. \(error.localizedDescription)"
        }
    }
}
