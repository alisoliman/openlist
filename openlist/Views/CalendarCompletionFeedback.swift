import SwiftUI

/// Completion feedback floats above content so it does not move the timeline.
/// The short-lived message and the window's normal Undo history are independent.
struct CalendarCompletionFeedback: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleID: UUID?

    var body: some View {
        Group {
            if let action = env.store.completionUndo, visibleID == action.id {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ListAccent.green.color)
                        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : visibleID)
                    Text(action.feedback)
                        .font(.callout).lineLimit(1)
                    Button("Undo") { _ = env.store.undoCompletion(action.id) }
                        .buttonStyle(.link).font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(maxWidth: 450)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .padding(.horizontal, 20).padding(.bottom, 40)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(action.isReopening ? "Tasks reopened" : "Tasks completed")
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.25), value: visibleID)
        .task(id: env.store.completionUndo?.id) {
            guard let action = env.store.completionUndo else { visibleID = nil; return }
            let remaining = action.expiresAt.timeIntervalSinceNow
            guard remaining > 0 else { visibleID = nil; return }
            visibleID = action.id
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            if visibleID == action.id { visibleID = nil }
        }
    }
}
