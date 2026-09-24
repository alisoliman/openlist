import SwiftUI

/// What a move of planned work would overlap, each with its time.
struct WorkMoveOverlapsView: View {
    let overlaps: [WorkMoveOverlap]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(overlaps) { overlap in
                VStack(alignment: .leading, spacing: 3) {
                    Text(overlap.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(NX.ink)
                    Text("\(NXFormat.dueLabel(overlap.start)) \(NXFormat.clock(overlap.start))–\(NXFormat.clock(overlap.end))")
                        .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
                }.accessibilityElement(children: .combine)
            }
        }
    }
}
