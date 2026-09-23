import SwiftUI

struct WorkPlanChangesView: View {
    let changes: [WorkPlanChange]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(NX.ink)
                    Text("\(change.previousStart.formatted(date: .abbreviated, time: .shortened)) → \(change.proposedStart?.formatted(date: .abbreviated, time: .shortened) ?? "No available slot")")
                        .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
                }.accessibilityElement(children: .combine)
            }
        }
    }
}
