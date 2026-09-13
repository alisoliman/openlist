import SwiftUI

enum CalendarSpan: String, CaseIterable, Identifiable {
    case day = "1 day", threeDays = "3 days", week = "1 week", month = "1 month"
    var id: String { rawValue }
    var days: Int { switch self { case .day: 1; case .threeDays: 3; case .week: 7; case .month: 28 } }
}
