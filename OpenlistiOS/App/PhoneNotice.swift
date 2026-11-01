//
//  PhoneNotice.swift
//  OpenlistiOS
//

import SwiftUI

/// What went wrong that the user should know about, at the top of the screen
/// as the Mac shows it above its window: a save that failed, a change the
/// Store refused, iCloud not starting. One at a time, the most serious first.
struct PhoneNotice: Equatable {
    let text: String
    /// Cleared on dismissal: a one-off refusal. The rest (a failed save,
    /// sync not starting) stay until what caused them changes, and only hide.
    let clears: Clearable?
    /// A save that failed, which Try Again makes again.
    var retriesSave = false

    enum Clearable: Equatable { case editorNotice, actionError, trashError, labelMaintenanceError }
}

extension PhoneEnvironment {
    var notice: PhoneNotice? {
        if let text = store.persistenceError { return PhoneNotice(text: text, clears: nil, retriesSave: true) }
        if let text = store.actionError { return PhoneNotice(text: text, clears: .actionError) }
        if let text = store.trashError { return PhoneNotice(text: text, clears: .trashError) }
        if let text = store.editorNotice { return PhoneNotice(text: text, clears: .editorNotice) }
        if let text = store.labelMaintenanceError { return PhoneNotice(text: text, clears: .labelMaintenanceError) }
        if let text = store.syncPreparationError ?? sync.startupWarning ?? sync.pushRegistrationError {
            return PhoneNotice(text: text, clears: nil)
        }
        return nil
    }

    func dismiss(_ notice: PhoneNotice) {
        switch notice.clears {
        case .editorNotice: store.editorNotice = nil
        case .actionError: store.actionError = nil
        case .trashError: store.trashError = nil
        case .labelMaintenanceError: store.labelMaintenanceError = nil
        case nil: break
        }
    }
}

/// The notice as a `dangerSoft` card under the status bar, with a close
/// button, and Try Again under a save that failed.
struct PhoneNoticeBanner: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.olStyle) private var style
    /// A notice that can't be cleared, hidden until its text changes.
    @State private var hidden: String?

    var body: some View {
        ZStack {
            if let notice = env.notice, notice.text != hidden {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OL.danger)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice.text)
                            .font(OLFont.note)
                            .foregroundStyle(OL.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if notice.retriesSave {
                            Button("Try Again", action: saveAgain)
                                .buttonStyle(.olLink(small: true))
                                // Its words in line with the text's, its 44 pt
                                // target over the text and the card's padding.
                                .padding(.leading, -10)
                                .padding(.vertical, -10)
                                .accessibilityIdentifier("notice.retry")
                        }
                    }
                    Button {
                        if notice.clears == nil { hidden = notice.text }
                        env.dismiss(notice)
                    } label: {
                        // A 44 pt target around the 32 pt button, which keeps
                        // its size in the layout.
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OL.muted)
                            .frame(width: 32, height: 32)
                            .padding(6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(OLPressStyle())
                    .padding(-6)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.vertical, 10)
                .background(OL.dangerSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, OLMetrics.gutter)
                .transition(style.reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notice")
                .onAppear { AccessibilityNotification.Announcement(notice.text).post() }
            }
        }
        .animation(style.fading(.snappy(duration: 0.3)), value: env.notice)
    }

    /// Saves again. A save that fails again may say the same words, so it's
    /// felt and, with VoiceOver, heard; one that works takes the notice away.
    private func saveAgain() {
        env.store.save()
        if let text = env.store.persistenceError {
            env.haptics.play(.error)
            AccessibilityNotification.Announcement(text).post()
        } else {
            env.haptics.play(.success)
        }
    }
}
