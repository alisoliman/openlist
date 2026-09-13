import SwiftUI

/// Attach existing labels or create a new one inline.
struct LabelPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Find or create a label", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.body)
                .onSubmit(createFromQuery)

            let matches = filteredLabels
            if !matches.isEmpty {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(matches) { label in
                            let labelID = label.id
                            Button {
                                env.store.toggleLabel(id: labelID, on: block)
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(label.accent.color)
                                        .frame(width: 8, height: 8)
                                    Text(label.name)
                                        .font(Theme.Font.body)
                                    Spacer()
                                    if block.labelIDs.contains(label.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            if canCreate {
                Button {
                    createFromQuery()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Create “\(TaskLabel.normalize(query))”")
                            .font(Theme.Font.body)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if filteredLabels.isEmpty, !canCreate {
                Text("No labels yet. Type a name to create one.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(12)
        .frame(width: 240)
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
