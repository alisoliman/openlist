//
//  NextCompletedFold.swift
//  openlist
//

import Foundation

/// The user's last fold of a Completed group this session. Today's, a
/// list's and a label's Completed groups fold as one, as the design's
/// single completedOpen, so the choice shows the same on every screen.
/// Until there is one, each screen opens its group as its own setting says:
/// a list's Completed Tasks choice, else Show completed tasks. Changing Show
/// completed tasks drops it (`NextShell`), so every group opens as that says.
struct NXCompletedFold {
    var open: Bool
    /// Lists whose Completed Tasks choice changed since the fold. There the
    /// new choice shows at once; the other screens keep the fold.
    var lapsed: Set<UUID> = []

    /// Whether a Completed group opens on a screen that would open it as
    /// `open`; `list` is the list the group sits under, if any.
    static func isOpen(_ fold: NXCompletedFold?, default open: Bool, list: UUID? = nil) -> Bool {
        guard let fold, !(list.map(fold.lapsed.contains) ?? false) else { return open }
        return fold.open
    }
}
