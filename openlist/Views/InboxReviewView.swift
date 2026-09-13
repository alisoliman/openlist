import SwiftData
import SwiftUI

/// A deliberate review session. Keeping or scheduling a task leaves it unfiled.
struct InboxReviewView: View {
    let inbox: TaskList
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" && !$0.isCompleted }, sort: \Block.sortIndex)
    private var tasks: [Block]
    @State private var reviewed: Set<UUID> = []
    @State private var destinationID: UUID?
    @State private var scheduledDate = Date.now
    @State private var notice: String?
    @State private var lastReviewedID: UUID?
    @State private var lastActionWasMutation = false
    @State private var lastUndoName = ""

    private var queue: [Block] {
        tasks.filter { $0.listID == inbox.id && $0.parentID == nil && !reviewed.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Review unfiled", systemImage: "tray.full").font(.headline)
                Spacer()
                Text("\(queue.count) remaining").font(.caption).foregroundStyle(.secondary)
            }
            if let task = queue.first {
                Text(task.displayTitle).font(.title2).textSelection(.enabled)
                if let dueDate = task.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: task.includesTime ? .shortened : .omitted), systemImage: "calendar")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Move it to a list, give it a date, or keep it here for later.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                HStack {
                    CaptureDestinationPicker(lists: env.store.allLists(), selection: $destinationID)
                    Button("Move to list") { move(task) }
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                        .disabled(destinationID == nil || destinationID == inbox.id)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Schedule", selection: $scheduledDate, displayedComponents: .date)
                        .datePickerStyle(.field)
                    HStack {
                        Button("Set date") { schedule(task, date: scheduledDate) }
                        Button("Today") { schedule(task, date: .now) }
                            .keyboardShortcut("t", modifiers: [.command, .shift])
                        Button("Tomorrow") {
                            schedule(task, date: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
                        }
                    }
                }
                HStack {
                    Button("Keep unfiled") { finish(task, notice: "Kept unfiled for later.", mutated: false) }
                        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                    Spacer()
                    Button("Open details") { env.navigator.openTask(task.id) }
                }
                Text("⇧⌘M move · ⇧⌘T today · ⇧⌘→ keep")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Unfiled review complete", systemImage: "checkmark.circle")
                    .font(.title3.weight(.semibold))
                Text("Tasks you kept or scheduled remain unfiled. You can review them again whenever you’re ready.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Review again") { reviewed = []; notice = nil }
            }
            if let notice {
                HStack(alignment: .top) {
                    Text(notice).font(.callout)
                    Spacer()
                    if lastReviewedID != nil, !lastActionWasMutation || (undoManager?.canUndo == true && undoManager?.undoActionName == lastUndoName) {
                        Button("Undo", action: undoLast)
                    }
                }
                .padding(10)
                .background(Theme.chipFill, in: .rect(cornerRadius: 8))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: queue.first?.id)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chipFill.opacity(0.45), in: .rect(cornerRadius: 14))
    }

    private func move(_ task: Block) {
        guard let list = env.store.list(id: destinationID), !list.isArchived, list.id != inbox.id else { return }
        env.store.undoableEditorEdit(in: Set([inbox.id, list.id]), name: "Move Unfiled task", undoManager: undoManager) {
            env.store.moveToList(task, list: list)
        }
        finish(task, notice: "Moved to \(list.displayTitle).", mutated: true)
    }

    private func schedule(_ task: Block, date: Date) {
        env.store.undoableEditorEdit(in: inbox.id, name: "Schedule Unfiled task", undoManager: undoManager) {
            env.store.setDueDate(Calendar.current.startOfDay(for: date), for: task)
        }
        finish(task, notice: "Scheduled for \(date.formatted(date: .abbreviated, time: .omitted)); kept unfiled.", mutated: true)
    }

    private func finish(_ task: Block, notice: String, mutated: Bool) {
        if mutated, let error = env.store.persistenceError {
            self.notice = "Changes aren’t saved yet. \(error)"
            return
        }
        reviewed.insert(task.id)
        lastReviewedID = task.id
        lastActionWasMutation = mutated
        lastUndoName = undoManager?.undoActionName ?? ""
        self.notice = notice
    }

    private func undoLast() {
        guard let lastReviewedID else { return }
        if lastActionWasMutation {
            guard undoManager?.undoActionName == lastUndoName else { return }
            undoManager?.undo()
        }
        reviewed.remove(lastReviewedID)
        self.lastReviewedID = nil
        notice = "Returned to the review queue."
    }
}
