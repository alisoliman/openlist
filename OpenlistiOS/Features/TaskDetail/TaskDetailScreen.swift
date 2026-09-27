//
//  TaskDetailScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Task detail (mockup 12), pushed. The shell's stub: the Detail feature adds
/// the editable title and note, the fields and the pickers.
struct TaskDetailScreen: View {
    let taskID: UUID
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        let task = env.store.block(id: taskID)
        OLScreen(identifier: PhoneRoute.taskDetail(taskID).screenIdentifier) {
            OLTopBar {
                OLBackButton(env.backTitle(for: .taskDetail(taskID))) { navigator.pop() }
            } trailing: {
                OLIconButton(task?.isStarred == true ? "star.fill" : "star", label: "Star", kind: .bare, iconSize: 22,
                             tint: task?.isStarred == true ? OL.today : OL.muted) {}
                OLIconButton("ellipsis", label: "More", kind: .bare, iconSize: 22) {}
            }
        } content: {
            HStack(alignment: .top, spacing: 14) {
                OLCheckbox(task?.isCompleted == true ? .done : .open, size: 28, title: task?.displayTitle ?? "") {
                    if let task { env.actions.toggle(task) }
                }
                Text(task?.displayTitle ?? "This task is gone")
                    .font(OLFont.detailTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            FeaturePlaceholder(summary: "The task’s fields come with the Detail feature.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OLActionDock {
                OLIconButton("trash", label: "Move to Trash", kind: .raised, size: .large) {
                    if let task, env.actions.trash([task]) { navigator.pop() }
                }
                Button {
                    navigator.open(.working)
                } label: {
                    Label("Start working", systemImage: "play.fill")
                }
                .buttonStyle(.ol(.primary, size: .large, block: true, glows: true))
            }
        }
    }
}
