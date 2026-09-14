import AppKit
import CoreData
import SwiftData
import SwiftUI

struct ActivityScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var heatmap: ActivityHeatmap?
    @State private var loadError: String?

    var body: some View {
        ScreenScaffold {
            ScreenHeader(icon: "square.grid.3x3.fill", title: "Activity", subtitle: "Recorded task completions") {
                Button("Refresh activity", systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.iconOnly)
                    .help("Refresh activity")
            }
        } content: {
            if let loadError {
                ContentUnavailableView {
                    Label("Activity unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try again", action: refresh)
                }
            } else if let heatmap {
                ActivityHeatmapView(heatmap: heatmap)
            } else {
                ProgressView("Loading activity…")
            }
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: env.settings.firstWeekday) { refresh() }
        .accessibilityIdentifier("activity-screen")
    }

    private func refresh() {
        var calendar = Calendar.current
        if env.settings.firstWeekday != 0 { calendar.firstWeekday = env.settings.firstWeekday }
        do {
            heatmap = try env.store.activityHeatmap(calendar: calendar)
            loadError = nil
        } catch {
            // Never leave stale totals presented as a successful refresh.
            heatmap = nil
            loadError = "Saved activity could not be read. \(error.localizedDescription)"
        }
    }
}
