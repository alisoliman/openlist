import SwiftUI

/// A small completion rail keeps progress visible without competing with tasks.
struct TodayProgressHeader: View {
    let done: Int
    let total: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 12) {
            if total == 0 {
                // Nothing due, planned or done today: no "0 of 0 done" and
                // empty rail over the clear day, which says so itself.
                OLTitle("Today")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    OLTitle("Today")
                    count
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    OLTitle("Today")
                    Spacer(minLength: 8)
                    count
                }
            }
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(OL.ink)
                    .accessibilityLabel("Today's progress")
                    .accessibilityValue("\(done) of \(total) done")
                    .accessibilityIdentifier("today.progress")
            }
        }
        .padding(.top, 4)
    }

    private var count: some View {
        Text("\(done) of \(total) done")
            .font(OLFont.meta)
            .foregroundStyle(OL.muted)
            .contentTransition(.numericText())
    }
}
