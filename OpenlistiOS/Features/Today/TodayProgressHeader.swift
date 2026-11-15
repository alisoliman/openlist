import SwiftUI

/// A small completion rail keeps progress visible without competing with tasks.
struct TodayProgressHeader<Actions: View>: View {
    let title: String
    let done: Int
    let total: Int
    @ViewBuilder var actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OLTopBar {
                OLTitle(title)
                    .padding(.leading, 10)
            } trailing: { actions }
            if total > 0 {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        count
                        rail
                    }
                } else {
                    HStack(spacing: 12) {
                        rail
                        count
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var rail: some View {
        ProgressView(value: Double(done), total: Double(total))
            .tint(OL.muted)
            .accessibilityLabel("\(title)’s progress")
            .accessibilityValue("\(done) of \(total) done")
            .accessibilityIdentifier("today.progress")
    }

    private var count: some View {
        Text("\(done) of \(total) done")
            .font(.caption.monospacedDigit())
            .foregroundStyle(OL.muted)
            .contentTransition(.numericText())
    }
}
