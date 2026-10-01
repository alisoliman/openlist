import SwiftUI
import UIKit

/// Swipe actions for card rows, including Inbox's own wording. A short right
/// swipe exposes two 44-point icon targets; continuing right arms Today.
struct PhoneTaskSwipe: ViewModifier {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @State private var width: CGFloat = 320
    @State private var offset: CGFloat = 0
    @State private var origin: CGFloat = 0
    @State private var armed: TaskSwipeMotion.Result?
    @State private var picksList = false

    private var completed: Bool { task.isCompleted || env.actions.isClosing(task.id) }
    private var allowsToday: Bool { env.actions.canAddToToday(task, hierarchy: library.hierarchy) }
    private var destinations: [TaskList] { library.lists.filter { $0.id != task.listID } }

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            controls
            content
                .background(OL.surface)
                .offset(x: offset)
                // A tap on the shifted row closes its controls instead of
                // accidentally opening or completing the task underneath.
                .overlay {
                    if offset != 0 {
                        Button("Close task actions") { close() }
                            .foregroundStyle(.clear)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(.rect)
                            .accessibilityIdentifier("task.swipe.close")
                            .offset(x: offset)
                    }
                }
        }
        .clipped()
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .gesture(HorizontalTaskPan(changed: drag))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task.swipe.\(task.displayTitle)")
        .accessibilityActions {
            if allowsToday, !task.isPlanned(on: env.now, calendar: env.settings.calendar) {
                Button("Add to Today") {
                    close()
                    env.actions.addToToday(task)
                }
            }
            ForEach([env.taskSwipes.first, env.taskSwipes.second].filter(isAvailable)) { action in
                Button(actionTitle(action)) { perform(action) }
            }
            Button("Move to Trash") {
                close()
                env.actions.trash([task])
            }
        }
        .onChange(of: env.openSwipeTaskID) { _, id in
            if id != task.id { reset() }
        }
        .onChange(of: task.isCompleted) { reset() }
        .onChange(of: task.listID) { reset() }
        .onDisappear {
            if env.openSwipeTaskID == task.id { env.openSwipeTaskID = nil }
        }
        .confirmationDialog("Move task to", isPresented: $picksList, titleVisibility: .visible) {
            ForEach(destinations) { list in
                Button(library.hierarchy.path(for: list.id)) {
                    env.actions.move([task], to: list)
                }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if offset > 0 {
            HStack(spacing: 8) {
                if armed == .today {
                    Label("Today", systemImage: "sun.max.fill")
                        .font(OLFont.meta)
                        .foregroundStyle(OL.todayText)
                        .padding(.leading, 10)
                        .accessibilityHidden(true)
                } else {
                    actionButton(env.taskSwipes.first, slot: "first")
                    actionButton(env.taskSwipes.second, slot: "second")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(armed == .today ? OL.todaySoft : OL.sunken)
        } else if offset < 0 {
            HStack {
                Spacer(minLength: 0)
                Button("Move to Trash", systemImage: "trash") {
                    close()
                    env.actions.trash([task])
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OL.onDanger)
                .frame(width: 44, height: 44)
                .background(OL.danger, in: .circle)
                .buttonStyle(.plain)
                .accessibilityIdentifier("task.swipe.delete")
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OL.dangerSoft)
        }
    }

    private func actionButton(_ action: TaskSwipeAction, slot: String) -> some View {
        let symbol = action == .star && task.isStarred ? "star.fill" : action == .complete && completed ? "arrow.uturn.backward" : action.symbol
        return Button(actionTitle(action), systemImage: symbol) { perform(action) }
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(action == .star ? OL.todayText : OL.accentText)
            .frame(width: 44, height: 44)
            .background(OL.surface, in: .circle)
            .buttonStyle(.plain)
            .disabled(!isAvailable(action))
            .opacity(isAvailable(action) ? 1 : 0.4)
            .accessibilityIdentifier("task.swipe.\(slot)")
    }

    private func actionTitle(_ action: TaskSwipeAction) -> String {
        if action == .star, task.isStarred { return "Unstar" }
        if action == .complete, completed { return "Reopen" }
        return action.title
    }

    private func isAvailable(_ action: TaskSwipeAction) -> Bool {
        switch action {
        case .moveToList: !destinations.isEmpty
        case .tomorrow, .startWorking: allowsToday
        case .star, .complete: true
        }
    }

    private func perform(_ action: TaskSwipeAction) {
        guard isAvailable(action) else { return }
        close()
        switch action {
        case .moveToList:
            picksList = true
        case .star:
            env.actions.edit([task], task.isStarred ? "Unstarred “\(task.displayTitle)”" : "Starred “\(task.displayTitle)”", icon: "star") {
                env.store.toggleStar($0)
            }
        case .tomorrow:
            guard allowsToday else { return }
            env.actions.schedule([task], on: PhoneDay.tomorrow.date(now: env.now, calendar: env.settings.calendar))
        case .startWorking:
            guard allowsToday else { return }
            if env.actions.startWork(task) { env.navigator.open(.working) }
        case .complete:
            env.actions.toggle(task)
        }
    }

    private func drag(_ state: UIGestureRecognizer.State, translation: CGFloat) {
        switch state {
        case .began:
            origin = offset
            env.openSwipeTaskID = task.id
            fallthrough
        case .changed:
            offset = min(width, max(-width, origin + translation))
            let result = TaskSwipeMotion.result(translation: translation, origin: origin, width: width, allowsToday: allowsToday)
            let nextArmed: TaskSwipeMotion.Result? = result == .today || result == .trash ? result : nil
            if nextArmed != armed, nextArmed != nil { env.haptics.play(.selection) }
            armed = nextArmed
        case .ended:
            let result = TaskSwipeMotion.result(translation: translation, origin: origin, width: width, allowsToday: allowsToday)
            armed = nil
            switch result {
            case .today:
                close()
                env.actions.addToToday(task)
            case .trash:
                close()
                env.actions.trash([task])
            case .shortcuts:
                settle(at: TaskSwipeMotion.shortcutsWidth)
            case .delete:
                settle(at: -TaskSwipeMotion.deleteWidth)
            case .closed:
                close()
            }
        case .cancelled, .failed:
            close()
        default:
            break
        }
    }

    private func settle(at value: CGFloat) {
        withAnimation(style.animation(.snappy(duration: 0.22))) { offset = value }
    }

    private func reset() {
        armed = nil
        settle(at: 0)
    }

    private func close() {
        reset()
        if env.openSwipeTaskID == task.id { env.openSwipeTaskID = nil }
    }
}

extension View {
    func phoneTaskSwipe(_ task: Block) -> some View { modifier(PhoneTaskSwipe(task: task)) }
}
