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
        let style = env.workbench.style
        VStack(alignment: .leading, spacing: 16) {
            NXPanelTitle("Merge labels?")
            if destinations.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    NXCapsTitle(text: "Keep this label")
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(destinations) { label in
                            let isOn = destinationID == label.id
                            Button { destinationID = label.id } label: {
                                HStack(spacing: 9) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(label.accent.color).frame(width: 8, height: 8).frame(width: 16)
                                    Text(label.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(label.accent.title) · created \(NXFormat.moment(label.createdAt))")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(NX.ink(0.45))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(NXPanelRowStyle(isOn: isOn))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(5)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Keep this label")
            }
            if let plan {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Replace “\(plan.source.name)” with the existing label below.")
                        .foregroundStyle(NX.ink(0.7))
                    // The inspector's chosen label pill.
                    HStack(spacing: 8) {
                        Text("#\(plan.destination.name)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(plan.destination.accent.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(plan.destination.accent.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NX.ink(0.5))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Surviving label: \(plan.destination.name), colour: \(plan.destination.accent.title)")
                    Text("This updates \(plan.affectedTaskCount) \(plan.affectedTaskCount == 1 ? "task" : "tasks"), including completed, nested, and archived tasks. The surviving label will be used by \(plan.resultingTaskCount) \(plan.resultingTaskCount == 1 ? "task" : "tasks") in total.")
                        .foregroundStyle(NX.ink(0.7))
                    Text("The existing label keeps its colour. Tasks using both labels keep one copy. Undo (⌘Z) takes the merge back.")
                        .foregroundStyle(NX.ink(0.5))
                }
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .medium))
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(NX.redText)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button("Merge labels", action: merge)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
                    .disabled(plan == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .presentationBackground(NX.card)
        .tint(style.accent)
        // A sheet over the Settings page, outside the Next shell's style.
        .environment(\.nextStyle, style)
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
            try env.workbench.mergeLabels(plan)
            dismiss()
        } catch {
            self.error = "The labels were not merged. \(error.localizedDescription)"
            refreshPlan()
        }
    }
}
