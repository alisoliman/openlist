import SwiftData
import SwiftUI

struct LabelMergeSheet: View {
    let request: LabelMergePlan.Request

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\TaskLabel.name)]) private var labels: [TaskLabel]
    @State private var destinationID: UUID?
    @State private var plan: LabelMergePlan?
    @State private var error: String?

    private var destinations: [TaskLabel] {
        labels.filter { $0.id != request.sourceID && TaskLabel.namesMatch($0.name, request.name) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Merge labels?")
                .font(NX.serif(26))
                .padding(.vertical, NX.serifLeading(26, lineHeight: 1.1))
                .foregroundStyle(NX.ink)
            if destinations.count > 1 {
                HStack(spacing: 8) {
                    Text("Keep this label").font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                    NXPopUpPill(value: destinations.first { $0.id == destinationID }.map(title) ?? "Choose",
                                label: "Keep this label", swatch: destinations.first { $0.id == destinationID }?.nxColor,
                                entries: destinations.map { label in
                                    .choice(title(label), isSelected: label.id == destinationID, swatch: label.nxColor) {
                                        destinationID = label.id
                                    }
                                })
                }
            }
            if let plan {
                Text("Replace “\(plan.source.name)” with the existing label below.")
                    .font(.system(size: 13))
                    .foregroundStyle(NX.ink(0.7))
                HStack(spacing: 5) {
                    Image(systemName: "tag.fill").font(.system(size: 11, weight: .semibold))
                    Text("\(plan.destination.name) · \(plan.destination.accent.title)")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(plan.destination.accent.color)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(plan.destination.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Surviving label: \(plan.destination.name), color: \(plan.destination.accent.title)")
                Text("This updates \(plan.affectedTaskCount) \(plan.affectedTaskCount == 1 ? "task" : "tasks"), including completed, nested, and archived tasks. The surviving label will be used by \(plan.resultingTaskCount) \(plan.resultingTaskCount == 1 ? "task" : "tasks") in total.")
                    .font(.system(size: 13))
                    .foregroundStyle(NX.ink(0.7))
                Text("The existing label keeps its color. Tasks using both labels keep one copy. You can undo this merge from the notice at the top of the window.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.48))
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(NX.redText)
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(NXDialogButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Merge labels", action: merge)
                    .buttonStyle(NXDialogButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(NX.card)
        .onAppear {
            destinationID = destinations.first?.id
            refreshPlan()
        }
        .onChange(of: destinationID) { refreshPlan() }
    }

    private func title(_ label: TaskLabel) -> String {
        "\(label.name) · \(label.accent.title) · created \(label.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func refreshPlan() {
        guard let destinationID else {
            plan = nil
            error = "There is no matching label to merge into. Close this dialog and try again."
            return
        }
        do {
            plan = try env.store.labelMergePlan(sourceID: request.sourceID, destinationID: destinationID)
        } catch {
            plan = nil
            self.error = error.localizedDescription
        }
    }

    private func merge() {
        guard let plan else { return }
        do {
            try env.store.mergeLabels(plan)
            dismiss()
        } catch {
            self.error = "The labels were not merged. \(error.localizedDescription)"
            refreshPlan()
        }
    }
}
