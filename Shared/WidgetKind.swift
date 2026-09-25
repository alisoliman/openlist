//
//  WidgetKind.swift
//  Shared between the app and the widget extension.
//

import Foundation

/// The widget kinds, shared so the app can reload only the widgets a change
/// affects. WidgetKit budgets reloads requested by an app in the background;
/// a plan that slides every few minutes must not spend Today's and Summary's.
nonisolated enum WidgetKind {
    static let today = "OpenlistToday"
    static let upNext = "OpenlistUpNext"
    static let quickAdd = "OpenlistQuickAdd"
    static let lists = "OpenlistLists"
    static let agenda = "OpenlistAgenda"
    static let summary = "OpenlistSummary"
    static let activity = "OpenlistActivity"

    /// Kinds that draw the day's plan and the work session.
    static let plan = [upNext, agenda]
    /// Kinds that draw tasks, counts, lists and completions.
    static let data = [today, quickAdd, lists, summary, activity]
}
