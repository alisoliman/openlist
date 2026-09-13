import SwiftUI

/// A task remains a local value until the user confirms this preview.
struct TaskCaptureView: View {
    let request: TaskCaptureRequest
    var closeWindow: (() -> Void)?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var draft = TaskCaptureDraft()
    @State private var destinationID: UUID?
    @State private var failure: String?
    @State private var savedTaskID: UUID?
    @State private var savedDestination = ""
    @State private var plansForToday = false
    @State private var titleFocus = CaptureTitleFocus()

    private var destination: TaskList? {
        let selected = env.store.list(id: destinationID)
        return selected?.isArchived == false ? selected : env.store.inboxList()
    }

    private var showsPreview: Bool {
        let preview = draft.preview
        return preview.title != draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            || preview.date != nil || preview.recurrence != nil || !preview.labels.isEmpty
            || draft.removesDate || draft.removesRecurrence || !draft.removedLabels.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("New task").font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close (Esc)")
            }

            if let savedTaskID {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Added to \(savedDestination)", systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ListAccent.green.color)
                    Text(draft.preview.title).font(.body).textSelection(.enabled)
                    HStack {
                        Button("Add another") { reset(preservingDestination: true) }
                            .keyboardShortcut(.return, modifiers: [])
                        Button("Open task") {
                            if let listID = env.store.block(id: savedTaskID)?.listID {
                                env.navigator.go(to: .list(listID))
                            }
                            env.navigator.openTask(savedTaskID)
                            openWindow(id: WindowID.main)
                            NSApp.activate(ignoringOtherApps: true)
                            close()
                        }
                        Spacer()
                        Button("Done", action: close).keyboardShortcut(.cancelAction)
                    }
                }
            } else {
                CaptureTitleField(text: $draft.text, focus: titleFocus, onSubmit: save, onCancel: close)
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("SAVE TO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        CaptureDestinationPicker(
                            lists: env.store.allLists(), selection: $destinationID,
                            onWillOpen: preserveTitleSelection,
                            onDidClose: restoreTitleSelection
                        )
                        if let suggestion = env.store.list(id: request.suggestedListID),
                           !suggestion.isArchived, !suggestion.isSystemInbox, suggestion.id != destination?.id {
                            Button("Use \(suggestion.displayTitle)") {
                                editMetadata { destinationID = suggestion.id }
                            }
                                .buttonStyle(.link)
                                .help("The list you were viewing; choose it to file here")
                        }
                    }
                    if destinationID != nil, destinationID != destination?.id {
                        Text("The selected list is unavailable. This task will go to Inbox.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if request.plansForToday {
                    Toggle("Plan for today", isOn: $plansForToday)
                        .toggleStyle(.checkbox)
                        .help("Include this task in today's calendar without setting a due date")
                        .onChange(of: plansForToday) { _, _ in
                            preserveTitleSelection()
                            restoreTitleSelection()
                        }
                }

                if showsPreview {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PREVIEW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(draft.preview.title).font(.body).textSelection(.enabled)
                        metadata
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.chipFill, in: .rect(cornerRadius: 12))
                }

                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(ListAccent.red.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Detect dates and repeats", isOn: $draft.parsesNaturalLanguage)
                    .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
                    .onChange(of: draft.parsesNaturalLanguage) { _, _ in
                        preserveTitleSelection()
                        restoreTitleSelection()
                    }

                HStack {
                    Text("Return to add · Esc to cancel")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add task", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destination == nil)
                        .accessibilityIdentifier("capture.save")
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 240)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: savedTaskID)
        .background(Theme.canvas)
        .onAppear { reset(text: request.text) }
        .onExitCommand(perform: close)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = draft.preview.date {
                removableChip(
                    date.formatted(date: .abbreviated, time: draft.preview.includesTime ? .shortened : .omitted),
                    symbol: "calendar", help: "Remove due date"
                ) { draft.removesDate = true }
            }
            if let recurrence = draft.preview.recurrence {
                removableChip(recurrence.displayText, symbol: "repeat", help: "Remove repeat rule") {
                    draft.removesRecurrence = true
                }
            }
            ForEach(draft.preview.labels, id: \.self) { name in
                removableChip(name, symbol: "tag", help: "Remove label \(name)") { draft.removedLabels.insert(name) }
            }
            if draft.removesDate || draft.removesRecurrence || !draft.removedLabels.isEmpty {
                Button("Restore detected details") {
                    editMetadata {
                        draft.removesDate = false
                        draft.removesRecurrence = false
                        draft.removedLabels = []
                    }
                }
                .font(.caption).buttonStyle(.link)
            }
        }
    }

    private func removableChip(_ title: String, symbol: String, help: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
            Button(help, systemImage: "xmark") { editMetadata(remove) }
                .labelStyle(.iconOnly).buttonStyle(.plain).help(help)
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.canvas, in: .capsule)
    }

    private func save() {
        guard savedTaskID == nil else { return }
        do {
            let block = try env.store.saveCapture(
                draft.preview, destinationID: destination?.id,
                selectedForDay: plansForToday ? .now : nil
            )
            savedTaskID = block.id
            savedDestination = destination?.displayTitle ?? "Inbox"
            failure = nil
        } catch {
            failure = "Task wasn’t added. \(error.localizedDescription) Your draft is still here; try again."
        }
    }

    private func reset(text: String = "", preservingDestination: Bool = false) {
        draft = TaskCaptureDraft(text: text, parsesNaturalLanguage: env.settings.parsesNaturalLanguageDates,
                                 dueTodayWhenUndated: !request.plansForToday && env.settings.defaultDestination == .today)
        plansForToday = request.plansForToday
        if !preservingDestination { destinationID = env.store.inboxList()?.id }
        failure = nil
        savedTaskID = nil
        titleFocus.reset(insertionPoint: (draft.text as NSString).length)
    }

    private func preserveTitleSelection() {
        titleFocus.preserveSelection()
    }

    private func restoreTitleSelection() {
        titleFocus.restoreSelection()
    }

    private func editMetadata(_ edit: () -> Void) {
        preserveTitleSelection()
        edit()
        restoreTitleSelection()
    }

    private func close() {
        if let closeWindow { closeWindow() } else { dismiss() }
    }
}
