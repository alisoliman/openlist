//
//  NextCompletedFold.swift
//  openlist
//

/// The user's last fold of a Completed group this session. Today's, a
/// list's and a label's Completed groups fold as one, as the design's
/// single completedOpen, so the choice shows the same on every screen.
/// Until there is one, each screen opens its group as its own setting says:
/// a list's Completed Tasks choice, else Show completed tasks.
struct NXCompletedFold {
    var open: Bool
    /// The Show completed tasks setting the fold was made under. Under the
    /// other one it has lapsed, so changing the setting shows at once.
    var showsCompleted: Bool

    /// Whether a Completed group opens on a screen that would open it as `open`.
    static func isOpen(_ fold: NXCompletedFold?, default open: Bool, showsCompleted: Bool) -> Bool {
        guard let fold, fold.showsCompleted == showsCompleted else { return open }
        return fold.open
    }
}
