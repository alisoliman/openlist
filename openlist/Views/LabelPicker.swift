import SwiftData
import SwiftUI

/// Attach existing labels or create a new one inline, through the workbench,
/// as the inspector's label chips do: one Undo step, with its tray. As the
/// design's small menus, a highlighted row is what Return picks: the best
/// match once something is typed, or the row ↑ and ↓ or the pointer move to.
/// Create comes last, so Return makes a label only when none holds the name.
struct LabelPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @State private var query = ""
    /// The row Return picks: a match's index, or the Create row after them.
    @State private var highlight: Int?

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        let choices = Self.choices(for: query, in: env.store.allLabels())
        let count = choices.matches.count + (choices.create == nil ? 0 : 1)
        return VStack(alignment: .leading, spacing: 6) {
            NXPanelField(icon: "number") {
                TextField("Find or create a label", text: $query)
                    .onSubmit { pick(highlight, in: choices) }
                    .onKeyPress(.downArrow) { move(1, count: count, in: choices) }
                    .onKeyPress(.upArrow) { move(-1, count: count, in: choices) }
            }
            .padding(.bottom, 2)

            if !choices.matches.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(choices.matches.enumerated()), id: \.element.id) { index, label in
                                let labelID = label.id
                                let isOn = block.labelIDs.contains(label.id)
                                Button {
                                    env.workbench.toggleLabel(block.id, labelID: labelID)
                                } label: {
                                    HStack(spacing: 9) {
                                        // The design's label mark, as the sidebar draws it.
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(label.accent.color)
                                            .frame(width: 8, height: 8)
                                            .frame(width: 16)
                                        Text(label.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(NXPanelRowStyle(isOn: isOn, isHighlighted: highlight == index))
                                .onHover { if $0 { highlight = index } }
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                                .id(labelID)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    // Keeps the row the arrows move to in sight.
                    .onChange(of: highlight) { _, index in
                        guard let index, choices.matches.indices.contains(index) else { return }
                        proxy.scrollTo(choices.matches[index].id)
                    }
                }
            }

            if let name = choices.create {
                let index = choices.matches.count
                Button {
                    pick(index, in: choices)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 16)
                        Text("Create “\(name)”")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(style.accent)
                }
                .buttonStyle(NXPanelRowStyle(isOn: false, isHighlighted: highlight == index))
                .onHover { if $0 { highlight = index } }
            }

            if count == 0 {
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
        // Typing puts the highlight on the best match, or on Create when none holds it.
        .onChange(of: query) { _, query in
            highlight = TaskLabel.normalize(query).isEmpty ? nil : 0
        }
    }

    /// What the picker lists for `query`: the labels holding it, the name
    /// itself first, then names starting with it, then the rest in library
    /// order; and the name Create makes when no label has it already.
    static func choices(for query: String, in labels: [TaskLabel]) -> (matches: [TaskLabel], create: String?) {
        let name = TaskLabel.normalize(query)
        guard !name.isEmpty else { return (labels, nil) }
        let needle = name.lowercased()
        func rank(_ label: TaskLabel) -> Int {
            if TaskLabel.namesMatch(label.name, name) { return 0 }
            return label.name.lowercased().hasPrefix(needle) ? 1 : 2
        }
        let matches = labels.enumerated()
            .filter { $0.element.name.lowercased().contains(needle) }
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        return (matches, labels.contains { TaskLabel.namesMatch($0.name, name) } ? nil : name)
    }

    /// ↑ and ↓ step through the rows and stop at either end; from none,
    /// they start at the first or the last.
    private func move(_ step: Int, count: Int, in choices: (matches: [TaskLabel], create: String?)) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        highlight = highlight.map { min(max($0 + step, 0), count - 1) } ?? (step > 0 ? 0 : count - 1)
        if let highlight {
            let name = choices.matches.indices.contains(highlight) ? "#\(choices.matches[highlight].name)"
                : choices.create.map { "Create “\($0)”" }
            if let name { AccessibilityNotification.Announcement(name).post() }
        }
        return .handled
    }

    /// Return, or the Create row: toggles the highlighted label, or makes the
    /// typed one, then clears the field for the next.
    private func pick(_ index: Int?, in choices: (matches: [TaskLabel], create: String?)) {
        guard let index else { return }
        if choices.matches.indices.contains(index) {
            env.workbench.toggleLabel(block.id, labelID: choices.matches[index].id)
        } else if index == choices.matches.count, choices.create != nil {
            env.workbench.addLabel(named: query, to: block.id)
        } else {
            return
        }
        query = ""
    }
}
