//
//  TrayCenter.swift
//  OpenlistiOS
//

import Foundation
import Observation

/// One message in the tray at the bottom of the screen: "Completed “Pay the
/// ryokan deposit”", "Restored to Home", with Undo while its window lasts.
struct TrayMessage: Identifiable, Equatable {
    /// The colour of the bar that drains under the message, by what happened.
    enum Tone: Equatable {
        case success, danger, warning, accent, neutral
    }

    let id = UUID()
    var text: String
    var icon: String?
    var tone: Tone = .success
    /// How long the message stays, which the drain bar counts down.
    var seconds: Double
    /// The button's title: "Undo", or an action such as "Open Trash".
    var actionTitle: String?
    /// When it appeared, so a view drawn later drains from the right place.
    var shownAt: Date = .now

    static func == (lhs: TrayMessage, rhs: TrayMessage) -> Bool { lhs.id == rhs.id }
}

/// The app's one tray. A new message replaces the one on show, in place, and
/// its drain starts over, as the Mac's tray does. VoiceOver announces each.
@Observable
@MainActor
final class TrayCenter {
    private(set) var message: TrayMessage?
    @ObservationIgnored private var action: (() -> Void)?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    /// Shows `text` for `seconds`. `action` runs if the button is tapped while
    /// it's on show (`actionTitle` defaults to "Undo" when there is one).
    @discardableResult
    func show(_ text: String, icon: String? = nil, tone: TrayMessage.Tone = .success, seconds: Double = 5,
              actionTitle: String? = nil, action: (() -> Void)? = nil) -> TrayMessage {
        let message = TrayMessage(text: text, icon: icon, tone: tone, seconds: seconds,
                                  actionTitle: action == nil ? nil : actionTitle ?? "Undo")
        self.message = message
        self.action = action
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(message.id)
        }
        return message
    }

    /// The button: runs the action once and takes the message down.
    func performAction() {
        let action = action
        dismiss(message?.id)
        action?()
    }

    /// Takes `id` down, or whatever is on show; a newer message stays.
    func dismiss(_ id: UUID? = nil) {
        guard let message, id == nil || id == message.id else { return }
        self.message = nil
        action = nil
        expiry?.cancel()
        expiry = nil
    }

    /// Whether `id` is still the message on show with its action available.
    func isActionAvailable(for id: UUID) -> Bool { message?.id == id && action != nil }
}
