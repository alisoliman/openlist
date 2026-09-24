//
//  ActivityBand.swift
//  Shared between the app and the widget extension.
//

/// The Activity heatmap's legend bands, so the Activity screen and the
/// Activity widget shade a day alike: none, 1, 2–3, 4–6 and 7 or more.
nonisolated enum ActivityBand {
    /// 0 for a day with no completions, up to 4 for seven or more.
    static func level(_ count: Int) -> Int {
        switch count {
        case ...0: 0
        case 1: 1
        case 2...3: 2
        case 4...6: 3
        default: 4
        }
    }
}
