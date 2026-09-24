import SwiftData
import SwiftUI

/// Attach existing labels or create a new one inline.
struct LabelPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @State private var query = ""

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            NXPanelField(icon: "number") {
                TextField("Find or create a label", text: $query)
                    .onSubmit(createFromQuery)
            }
            .padding(.bottom, 2)

            let matches = filteredLabels
            if !matches.isEmpty {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(matches) { label in
                            let labelID = label.id
                            let isOn = block.labelIDs.contains(label.id)
                            Button {
                                env.store.toggleLabel(id: labelID, on: block)
                            } label: {
                                HStack(spacing: 9) {
                                    Circle()
                                        .fill(label.accent.color)
                                        .frame(width: 8, height: 8)
                                        .frame(width: 16)
                                    Text(label.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(NXPanelRowStyle(isOn: isOn))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if canCreate {
                Button {
                    createFromQuery()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 16)
                        Text("Create “\(TaskLabel.normalize(query))”")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(style.accent)
                }
                .buttonStyle(NXPanelRowStyle(isOn: false))
            }

            if filteredLabels.isEmpty, !canCreate {
                Text("No labels yet. Type a name to create one.")
                    .font(.system(size: 12))
                    .foregroundStyle(NX.ink(0.45))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
        }
        .padding(6)
        .frame(width: 250)
        .presentationBackground(NX.card)
    }

    private var filteredLabels: [TaskLabel] {
        let needle = TaskLabel.normalize(query).lowercased()
        let all = env.store.allLabels()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(needle) }
    }

    private var canCreate: Bool {
        let name = TaskLabel.normalize(query)
        guard !name.isEmpty else { return false }
        return env.store.matchingLabels(named: name).isEmpty
    }

    private func createFromQuery() {
        guard let label = env.store.findOrCreateLabel(named: query) else { return }
        env.store.addLabel(label, to: block)
        query = ""
    }
}
