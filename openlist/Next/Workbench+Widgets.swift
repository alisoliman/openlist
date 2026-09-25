//
//  Workbench+Widgets.swift
//  openlist
//

import Foundation

/// Widget links land the way the main window's own navigation does.
extension Workbench: WidgetLinkScreens {}

/// Widget buttons act as the window's own rows and work controls do, so the
/// tray, the change log and Undo treat them alike.
extension Workbench: WidgetTaskActions {
    func completeFromWidget(_ id: UUID, at date: Date, now: Date) {
        complete([id], settleNow: true, at: date, clearsSelection: false)
    }

    func reopenFromWidget(_ id: UUID, now: Date) {
        reopen([id])
    }

    func startWorkFromWidget(_ id: UUID, now: Date) {
        startWork(id)
    }

    func pauseWorkFromWidget(now: Date) {
        guard calendar.activeSession != nil else { return }
        toggleWorkPause()
    }

    func settleCompletion(_ id: UUID) {
        settleClosing(of: id)
    }
}
