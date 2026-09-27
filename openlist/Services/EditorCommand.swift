//
//  EditorCommand.swift
//  openlist
//

import Foundation

/// One-shot instructions sent from menus and shortcuts down into whichever
/// document view is on screen.
enum EditorCommand: Equatable {
    case toggleCompletion
    case openDetails
    case setDueToday
    case pickDueDate
    case clearDueDate
    case pickLabel
    case clearLabels
    case toggleStar
    case indent
    case outdent
    case moveUp
    case moveDown
    case deleteSelection
    case expandAll
    case collapseAll
}
