//
//  PhoneHaptics.swift
//  OpenlistiOS
//

import UIKit

/// Haptic feedback from code, for actions that aren't a view's state change:
/// a bulk action landing, a hold committing, an Undo. Views use
/// `.olFeedback(_:trigger:)`. Both stay silent while the Haptics setting is off.
@MainActor
final class PhoneHaptics {
    enum Feedback: Equatable {
        /// A task completed, a capture added, a bulk action done.
        case success
        /// Something refused or failed.
        case error
        /// Before something that can't be undone, such as erasing for good.
        case warning
        /// A tab, day or chip picked.
        case selection
        /// A star, a hold starting.
        case impact
        /// An Undo.
        case soft
    }

    private let isEnabled: () -> Bool
    /// The last feedback played, for tests.
    private(set) var lastPlayed: Feedback?

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
    }

    convenience init(settings: AppSettings) {
        self.init { [weak settings] in settings?.playsHaptics ?? false }
    }

    func play(_ feedback: Feedback) {
        guard isEnabled() else { return }
        lastPlayed = feedback
        switch feedback {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .impact: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}
