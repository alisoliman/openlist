import SwiftUI
import UIKit

/// Swipe actions for card rows, including Inbox's own wording. A short right
/// swipe exposes two 44-point icon targets; continuing right arms Today. A
/// short left swipe exposes Trash; continuing left arms it.
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
                        Button { close() } label: {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close task actions")
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
        // Every list, found by name, the one triage would suggest first.
        .sheet(isPresented: $picksList) {
            ListPickerSheet(title: "Move to", excluding: Set([task.listID].compactMap(\.self)),
                            suggested: library.suggestedDestination(for: task)) { list in
                env.actions.move([task], to: list)
            }
        }
        // Somewhere else taking the screen takes the question with it.
        .onChange(of: env.navigator.arrivals) { picksList = false }
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
                if armed == .trash {
                    Label("Trash", systemImage: "trash.fill")
                        .font(OLFont.meta)
                        .foregroundStyle(OL.onDanger)
                        .padding(.trailing, 6)
                        .accessibilityHidden(true)
                } else {
                    circleButton("Move to Trash", symbol: "trash", ink: OL.onDanger, fill: OL.danger) {
                        close()
                        env.actions.trash([task])
                    }
                    .accessibilityIdentifier("task.swipe.delete")
                }
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(armed == .trash ? OL.danger : OL.dangerSoft)
        }
    }

    /// A shortcut that can't apply stays dimmed but tappable, and says why.
    private func actionButton(_ action: TaskSwipeAction, slot: String) -> some View {
        let symbol = action == .star && task.isStarred ? "star.fill" : action == .complete && completed ? "arrow.uturn.backward" : action.symbol
        return circleButton(actionTitle(action), symbol: symbol, ink: action == .star ? OL.todayText : OL.accentText,
                            fill: OL.surface) { perform(action) }
            .opacity(isAvailable(action) ? 1 : 0.4)
            .accessibilityIdentifier("task.swipe.\(slot)")
    }

    /// A revealed action: its glyph on a 44 pt disc, all of which is the target.
    private func circleButton(_ title: String, symbol: String, ink: Color, fill: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background(fill, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func actionTitle(_ action: TaskSwipeAction) -> String {
        if action == .star, task.isStarred { return "Unstar" }
        if action == .complete, completed { return "Reopen" }
        return action.title
    }

    private func isAvailable(_ action: TaskSwipeAction) -> Bool {
        switch action {
        case .moveToList: library.lists.contains { $0.id != task.listID }
        case .tomorrow, .startWorking: allowsToday
        case .star, .complete: true
        }
    }

    /// Says for 3 s in the tray why `action` can't apply to the task now, or
    /// with nil why Today can't have it: there's no other list, the task is
    /// done, or its list is archived.
    private func explainUnavailable(_ action: TaskSwipeAction?) {
        let reason: String
        if action == .moveToList {
            reason = "There’s no other list to move it to"
        } else if completed {
            reason = "“\(task.displayTitle)” is done"
        } else if let list = library.list(task.listID), !library.hierarchy.activeIDs.contains(list.id) {
            reason = "“\(list.displayTitle)” is archived"
        } else {
            reason = "“\(task.displayTitle)” can’t be planned now"
        }
        env.tray.show(reason, icon: "exclamationmark.circle", tone: .neutral, seconds: 3)
    }

    private func perform(_ action: TaskSwipeAction) {
        guard isAvailable(action) else { return explainUnavailable(action) }
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

    private func drag(_ state: UIGestureRecognizer.State, translation: CGFloat, velocity: CGFloat) {
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
            let result = TaskSwipeMotion.result(translation: translation, origin: origin, width: width,
                                                allowsToday: allowsToday, velocity: velocity)
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
                // A full swipe that can't add to Today says why rather than nothing.
                if !allowsToday, TaskSwipeMotion.result(translation: translation, origin: origin, width: width) == .today {
                    explainUnavailable(nil)
                }
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
