//
//  TaskDetailSheets.swift
//  OpenlistiOS
//

import SwiftUI

/// Task detail's Labels: every label to tick on or off, and a new one by name.
/// Each tick is one step with Undo in the tray. A name typed and not yet
/// added is added as the sheet goes, however it goes.
struct LabelPickerSheet: View {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var naming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Labels").font(OLFont.linkStrong)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.olLink(strong: true))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 14)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(library.labels.enumerated()), id: \.element.id) { index, label in
                        let isOn = task.labelIDs.contains(label.id)
                        Button { toggle(label, isOn: isOn) } label: {
                            OLSettingsRow("#\(label.name)", separator: index == 0 ? .none : .inset(16)) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isOn ? OL.accent : OL.lineStrong)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(OLRowPressStyle())
                        .accessibilityLabel("#\(label.name)")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "plus").foregroundStyle(OL.muted)
                        TextField("New label", text: $name)
                            .font(OLFont.rowTitle)
                            .textInputAutocapitalization(.never)
                            // A label is a name, not a word to correct.
                            .autocorrectionDisabled()
                            .focused($naming)
                            .submitLabel(.done)
                            .onSubmit {
                                addNew()
                                naming = true
                            }
                            .accessibilityIdentifier("labels.new")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                    .onTapGesture { naming = true }
                    .overlay(alignment: .top) { OLSeparatorLine(separator: library.labels.isEmpty ? .none : .inset(16)) }
                }
                .olCard()
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, OLMetrics.gutter)
        .presentationDetents([.medium, .large])
        .olSheet()
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { dismiss() }
        .onDisappear(perform: addNew)
    }

    private func toggle(_ label: TaskLabel, isOn: Bool) {
        let text = isOn ? "Removed #\(label.name) · “\(task.displayTitle)”" : "Added #\(label.name) · “\(task.displayTitle)”"
        env.actions.edit([task], text, icon: "number") { env.store.toggleLabel(id: label.id, on: $0) }
    }

    private func addNew() {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !typed.isEmpty, let label = env.store.findOrCreateLabel(named: typed) else { return }
        name = ""
        if !task.labelIDs.contains(label.id) { toggle(label, isOn: false) }
    }
}

/// A task's saved history, newest first: what changed, the detail, and when,
/// as the Mac's inspector lists it, pushed from the task's page, with all
/// activity a step on.
struct TaskHistoryScreen: View {
    let taskID: UUID
    @Environment(PhoneEnvironment.self) private var env
    @State private var events: [ActivityEvent] = []
    @State private var limit = 50
    /// Why the history couldn't be read, in place of saying nothing changed.
    @State private var loadError: String?

    var body: some View {
        let navigator = env.navigator
        let now = env.now
        let route = PhoneRoute.taskHistory(taskID)
        OLScreen(identifier: route.screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: route)) { navigator.pop() } }
        } content: {
            if let task = env.store.block(id: taskID), task.isTask {
                OLHeader("History", sub: task.displayTitle)
                Text("Created \(NXFormat.moment(task.createdAt, now: now))"
                     + (task.completedAt.map { " · Completed \(NXFormat.moment($0, now: now))" } ?? ""))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .padding(.horizontal, 4)
                    .padding(.top, OLMetrics.headerGap)
                    .padding(.bottom, 8)
                if let loadError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loadError).font(OLFont.note).foregroundStyle(OL.muted)
                        Button("Try Again", action: load).buttonStyle(.olLink())
                    }
                    .padding(.horizontal, 4)
                } else if events.isEmpty {
                    Text("Nothing else has changed yet.")
                        .font(OLFont.note)
                        .foregroundStyle(OL.muted)
                        .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            row(event, now: now)
                                .overlay(alignment: .top) { OLSeparatorLine(separator: index == 0 ? .none : .plain) }
                        }
                    }
                    .olCard()
                    if events.count >= limit {
                        Button("Show older") {
                            limit += 50
                            load()
                        }
                        .buttonStyle(.olLink())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                }
                // Everything else that happened, day by day.
                OLLinkRow("All activity", topSpacing: 12) { navigator.open(.activity) }
                    .accessibilityIdentifier("history.activity")
            } else {
                OLEmptyState(symbol: "questionmark", tint: OL.muted, title: "This task is gone",
                             message: "It was moved to Trash or deleted on another device.")
                    .padding(.top, 80)
            }
        }
        .onAppear(perform: load)
    }

    private func row(_ event: ActivityEvent, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(event.kind.verb) “\(event.title)”")
                .font(OLFont.note)
                .foregroundStyle(OL.ink)
            let detail = event.recordedDetail
            if !detail.isEmpty {
                Text(detail).font(OLFont.meta).foregroundStyle(OL.muted)
            }
            Text(NXFormat.moment(event.timestamp, now: now))
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func load() {
        do {
            events = try env.store.taskActivity(for: taskID, limit: limit)
            loadError = nil
        } catch {
            loadError = "This task’s history couldn’t be read. \(error.localizedDescription)"
        }
    }
}

/// Plan at a time: the day and time a task's slot starts, as dropping it on
/// the timeline sets, for anyone not dragging. It runs for the task's
/// estimate.
struct PlanAtSheet: View {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OLSheetHeader(confirmTitle: "Plan", cancel: { dismiss() }) {
                if env.actions.place(task, at: start) { dismiss() }
            }
            Text("Plan at a time").font(OLFont.groupHeader).foregroundStyle(OL.muted).padding(.top, 6)
            DatePicker("Starts", selection: $start, in: env.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .tint(OL.accent)
                .padding(.top, 6)
                .accessibilityIdentifier("planAt.start")
            Text("For \(CompactText.estimate(env.actions.planMinutes(for: task))), its estimate.")
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .presentationDetents([.large])
        .olSheet()
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear { start = Self.nextQuarterHour(after: env.now, calendar: env.settings.calendar) }
    }

    /// The quarter hour after `now`: 10:40 starts at 10:45, 10:45 at 11:00.
    static func nextQuarterHour(after now: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = calendar.date(from: parts) ?? now
        return calendar.date(byAdding: .minute, value: 15 - (parts.minute ?? 0) % 15, to: minute) ?? now
    }
}
