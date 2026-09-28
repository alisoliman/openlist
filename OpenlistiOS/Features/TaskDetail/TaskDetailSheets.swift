//
//  TaskDetailSheets.swift
//  OpenlistiOS
//

import SwiftUI

/// Task detail's Labels: every label to tick on or off, and a new one by name.
/// Each tick is one step with Undo in the tray.
struct LabelPickerSheet: View {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Labels").font(OLFont.linkStrong)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.olLink(strong: true))
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
                            .submitLabel(.done)
                            .onSubmit(addNew)
                            .accessibilityIdentifier("labels.new")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
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
/// as the Mac's inspector lists it.
struct TaskHistorySheet: View {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var events: [ActivityEvent] = []
    @State private var limit = 50

    var body: some View {
        let now = env.now
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History").font(OLFont.linkStrong)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.olLink(strong: true))
            }
            .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Created \(NXFormat.moment(task.createdAt, now: now))"
                         + (task.completedAt.map { " · Completed \(NXFormat.moment($0, now: now))" } ?? ""))
                        .font(OLFont.meta)
                        .foregroundStyle(OL.muted)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    if events.isEmpty {
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
                        }
                    }
                    // Everything else that happened, day by day.
                    OLLinkRow("All activity", topSpacing: 12) {
                        dismiss()
                        env.navigator.open(.activity)
                    }
                    .accessibilityIdentifier("history.activity")
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, OLMetrics.gutter)
        .presentationDetents([.medium, .large])
        .olSheet()
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
        events = (try? env.store.taskActivity(for: task.id, limit: limit)) ?? []
    }
}
