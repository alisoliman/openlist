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
        case let .list(id): return env.store.blocks(inList: id)
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
                Text("Create an independent copy with all nested tasks, notes and files. Tasks start incomplete, with no due dates, reminders or calendar placements.")
                    .foregroundStyle(NX.ink(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Labels, priority, stars and formatting are kept. The original stays unchanged.")
                    .foregroundStyle(NX.ink(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .lineSpacing(2)
            if sources.contains(where: { $0.recurrence != nil }) {
                // A settings row: the design's 500 13px label and 11.5px hint beside its switch.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep repeating rules")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NX.ink)
                        Text("Repeats start with zero completions and no end date. Choose a new due date after copying.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(NX.ink(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NXToggle(isOn: keepsRecurrence, label: "Keep repeating rules") { keepsRecurrence.toggle() }
                        .accessibilityIdentifier("template-keep-recurrence")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
                .contentShape(Rectangle())
                .onTapGesture { keepsRecurrence.toggle() }
            }
            if let error {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(NX.redText)
                    .fixedSize(horizontal: false, vertical: true)
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
            let mode = CopyMode.template(keepingRecurrence: keepsRecurrence)
            switch request.source {
            case let .task(id):
                guard let task = env.store.block(id: id), task.isTask,
                      let listID = task.listID else { throw CopyError.unavailable }
                let outcome = env.store.undoableEditorEdit(in: listID, name: "Use task as template", undoManager: request.undoManager) {
                    Result { try env.store.copyBlock(task, mode: mode) }
                }
                let copyID = try outcome.get()
                dismiss()
                env.showCopiedTask(id: copyID, listID: listID)
            case let .list(id):
                guard let list = env.store.list(id: id) else { throw CopyError.unavailable }
                let copyID = try env.store.copyList(list, mode: mode)
                dismiss()
                env.navigator.go(to: .list(copyID))
            }
        } catch {
            self.error = "The copy was not created. \(error.localizedDescription)"
        }
    }
}
