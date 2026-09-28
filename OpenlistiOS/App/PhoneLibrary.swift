//
//  PhoneLibrary.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// The library every screen draws, built once a render from the root's
/// queries, as the Mac's shell builds its `NextLibrary`: the same lists,
/// labels and tasks, live as edits and CloudKit imports land.
struct PhoneLibraryHost<Content: View>: View {
    @Query(filter: TaskList.availablePredicate) private var lists: [TaskList]
    @Query(filter: #Predicate<SidebarSection> { $0.mergedIntoID == nil }) private var sections: [SidebarSection]
    @Query private var labels: [TaskLabel]
    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" }) private var tasks: [Block]
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.environment(\.phoneLibrary, NextLibrary(lists: lists, sections: sections, labels: labels, tasks: tasks))
    }
}

extension EnvironmentValues {
    /// The root's library, which sheets and covers are handed too.
    @Entry var phoneLibrary = NextLibrary()
}

extension NextLibrary {
    /// A task's subtasks that are tasks, in any state.
    func subtasks(of task: Block) -> [Block] {
        guard let listID = task.listID else { return [] }
        return tasks(in: listID).filter { $0.parentID == task.id && $0.isTask }
    }
}
