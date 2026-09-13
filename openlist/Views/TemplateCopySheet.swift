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
            Text("Use as template").font(.title2.weight(.semibold))
            Text(sourceTitle).font(.headline).lineLimit(3)
            Text("Create an independent copy with all nested tasks, notes and files. Tasks start incomplete, with no due dates, reminders or calendar placements.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Labels, priority, stars and formatting are kept. The original stays unchanged.")
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if sources.contains(where: { $0.recurrence != nil }) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Keep repeating rules", isOn: $keepsRecurrence)
                        .accessibilityIdentifier("template-keep-recurrence")
                    Text("Repeats start with zero completions and no end date. Choose a new due date after copying.")
                        .font(.callout).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("template-copy-error")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create copy", action: createCopy)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("template-create-copy")
            }
        }
        .padding(24)
        .frame(width: 430)
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
