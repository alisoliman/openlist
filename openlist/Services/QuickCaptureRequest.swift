//
//  QuickCaptureRequest.swift
//  openlist
//

import Foundation

/// What a widget asks of Quick Add: a list, or today, or neither for Inbox
/// with no date. The hot key, the menu bar and File ▸ Quick Add ask nothing.
struct QuickCaptureRequest: Equatable {
    /// The list the card starts on; Inbox when nil.
    var listID: UUID?
    /// Makes a task with no date of its own due today, as Today's add row
    /// does, so it shows in the Today widget that asked.
    var dueToday = false
}
