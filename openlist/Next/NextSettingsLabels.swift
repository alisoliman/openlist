//
//  NextSettingsLabels.swift
//  openlist
//
//  Settings' Labels group: add, rename, recolour, merge and delete labels.
//

import SwiftData
import SwiftUI

struct NXLabelSettings: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var labels: [TaskLabel]

    @State private var newLabelName = ""
    @State private var mergeRequest: LabelMergePlan.Request?

    var body: some View {
        NXSettingsGroup(title: "Labels") {
            NXSettingLine {
                Image(systemName: "tag")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NX.ink(0.35))
                NXSettingField(placeholder: "New label name", text: $newLabelName, onSubmit: create)
                Button("Add", action: create)
                    .disabled(TaskLabel.normalize(newLabelName).isEmpty)
            }
            if labels.isEmpty {
                NXSettingRow(label: "No labels yet", hint: "Add one above, or type #something in any task.")
            } else {
                ForEach(labels) { label in
                    NXLabelSettingsRow(label: label) { name in
                        mergeRequest = .init(sourceID: label.id, name: name)
                    }
                }
            }
        }
        .sheet(item: $mergeRequest) { request in
            LabelMergeSheet(request: request)
        }
    }

    private func create() {
        guard let label = env.store.findOrCreateLabel(named: newLabelName) else { return }
        _ = label
        env.store.save()
        newLabelName = ""
    }
}

/// A label's colour, its name to edit in place, how many items use it, and
/// its merge and delete actions.
private struct NXLabelSettingsRow: View {
    let label: TaskLabel
    let requestMerge: (String) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var nameDraft = SyncedTextDraft()
    @State private var colorMenu = NXMenuAnchor()
    @State private var hoversColor = false
    @FocusState private var isEditing: Bool

    var body: some View {
        NXSettingLine {
            Circle()
                .fill(label.nxColor)
                .frame(width: 11, height: 11)
                .frame(width: 22, height: 22)
                .background(NX.ink(hoversColor ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .background { NXMenuAnchorView(anchor: colorMenu) }
                .overlay { NXMenuPress(action: chooseColor) }
                .onHover { hoversColor = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Color for label \(label.name)")
                .accessibilityValue(label.accent.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { chooseColor() }
                .help("Change color for \(label.name)")

            TextField("Name", text: $nameDraft.value)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NX.ink)
                .focused($isEditing)
                .accessibilityLabel("Label name")
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if editing {
                        nameDraft.reset(to: label.name)
                    } else {
                        commit()
                    }
                }

            Text("\(env.store.blockCount(for: label))")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NX.ink(0.42))
                .monospacedDigit()

            if !env.store.matchingLabels(named: label.name, excluding: label.id).isEmpty {
                Button("Merge duplicates") { requestMerge(label.name) }
                    .help("Choose a matching label to keep")
            }

            Button {
                env.store.deleteLabel(label)
            } label: {
                Image(systemName: "trash").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.red.opacity(0.1), radius: 6,
                                            padding: EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5),
                                            foreground: NX.ink(0.4), hoverForeground: NX.redText))
            .accessibilityLabel("Delete label \(label.name)")
            .help("Delete label \(label.name)")
        }
        .onAppear {
            nameDraft.reset(to: label.name)
        }
        .onChange(of: label.name) { _, name in
            nameDraft.receive(name)
        }
    }

    private func chooseColor() {
        let entries: [NXMenuEntry] = ListAccent.allCases.map { accent in
            .choice(accent.title, isSelected: label.accent == accent, swatch: accent.color) {
                env.store.setAccent(accent, for: label)
            }
        }
        colorMenu.popUp(entries, titleInset: 0, dropsDown: true)
    }

    private func commit() {
        guard !label.isDeleted, label.modelContext != nil else { return }
        guard let trimmed = nameDraft.editedValue(normalize: TaskLabel.normalize), trimmed != label.name else {
            nameDraft.reset(to: label.name)
            return
        }
        if !trimmed.isEmpty, !env.store.matchingLabels(named: trimmed, excluding: label.id).isEmpty {
            nameDraft.reset(to: label.name)
            requestMerge(trimmed)
            return
        }
        do {
            try env.store.renameLabel(label, to: trimmed)
        } catch {
            env.store.labelMaintenanceError = "The label was not renamed. \(error.localizedDescription)"
        }
        nameDraft.reset(to: label.name)
    }
}
