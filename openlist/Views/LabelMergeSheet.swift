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
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge labels?").font(.title2.bold())
            if destinations.count > 1 {
                Picker("Keep this label", selection: $destinationID) {
                    ForEach(destinations) { label in
                        Text("\(label.name) · \(label.accent.title) · created \(label.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .tag(Optional(label.id))
                    }
                }
            }
            if let plan {
                Text("Replace “\(plan.source.name)” with the existing label below.")
                Label("\(plan.destination.name) · \(plan.destination.accent.title)", systemImage: "tag.fill")
                    .foregroundStyle(plan.destination.accent.color)
                    .font(.headline)
                    .accessibilityLabel("Surviving label: \(plan.destination.name), color: \(plan.destination.accent.title)")
                Text("This updates \(plan.affectedTaskCount) \(plan.affectedTaskCount == 1 ? "task" : "tasks"), including completed, nested, and archived tasks. The surviving label will be used by \(plan.resultingTaskCount) \(plan.resultingTaskCount == 1 ? "task" : "tasks") in total.")
                Text("The existing label keeps its color. Tasks using both labels keep one copy. You can undo this merge after leaving Settings.")
                    .foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Merge labels", action: merge)
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            destinationID = destinations.first?.id
            refreshPlan()
        }
        .onChange(of: destinationID) { refreshPlan() }
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
