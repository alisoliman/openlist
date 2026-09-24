//
//  UpNextWidgetView.swift
//  OpenlistWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// The block to be on now, with Start, Pause and Done. Medium adds what's
/// later today.
struct UpNextWidgetView: View {
    let model: UpNextModel
    let size: WidgetSize
    let date: Date
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetIsPreview) private var freezesTime

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            main
                .frame(width: size == .medium ? 168 : nil)
                .frame(maxWidth: size == .medium ? nil : .infinity, maxHeight: .infinity, alignment: .topLeading)
            if size == .medium {
                HStack(alignment: .top, spacing: 0) {
                    Hairline()
                    later.padding(.leading, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var isWorking: Bool { model.state == .working || model.state == .paused }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(model.state == .paused ? palette.amber : palette.acc)
                    .widgetAccentable()
                    .frame(width: 7, height: 7)
                Text(model.label.uppercased())
                    .tracking(10 * 0.08)
                    .css(.sans(10, .bold), line: 1)
                    .foregroundStyle(palette.acc)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(model.time)
                    .css(.mono(10, .medium), line: 1)
                    .foregroundStyle(palette.sub)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(model.title)
                .css(.sans(15, .semibold), line: 1.25)
                .foregroundStyle(palette.ink)
                .lineLimit(3)
                .padding(.top, 10)
            Text(listLine)
                .css(.sans(10.5, .medium), line: 1.2)
                .foregroundStyle(palette.solid)
                .opacity(palette.subOpacity)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 4)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    elapsed
                    ThinBar(progress: model.progress, color: palette.acc)
                        .invalidatableContent()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
        }
    }

    private var listLine: String {
        (palette.isDimmed || model.listIcon.isEmpty ? "" : model.listIcon + " ") + model.listName
    }

    @ViewBuilder private var elapsed: some View {
        if let timer = model.timer {
            Group {
                switch timer {
                case let .running(anchor) where !freezesTime:
                    Text(.currentDate, format: .stopwatch(startingAt: anchor, showsHours: false, maxPrecision: .seconds(1)))
                case let .running(anchor):
                    Text(date, format: .stopwatch(startingAt: anchor, showsHours: false, maxPrecision: .seconds(1)))
                case let .paused(seconds):
                    let anchor = Date(timeIntervalSinceReferenceDate: 0)
                    Text(anchor.addingTimeInterval(seconds), format: .stopwatch(startingAt: anchor, showsHours: false, maxPrecision: .seconds(1)))
                }
            }
            .monospacedDigit()
            .css(.mono(19, .semibold), line: 1)
            .foregroundStyle(palette.acc)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .invalidatableContent()
        } else {
            Text(model.note)
                .css(.sans(11, .medium), line: 1)
                .foregroundStyle(palette.sub)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var buttons: some View {
        if let taskID = model.taskID {
            if isWorking {
                HStack(spacing: 5) {
                    Button(intent: ToggleWorkPauseIntent(taskID: taskID, occurrenceID: model.occurrenceID)) {
                        disc(palette.chip) {
                            WidgetSymbol(name: model.state == .paused ? "play.fill" : "pause.fill", size: 12, color: palette.ink)
                        }
                    }
                    .accessibilityLabel(model.state == .paused ? "Resume" : "Pause")
                    Button(intent: FinishWorkIntent(taskID: taskID, occurrenceID: model.occurrenceID)) {
                        disc(palette.green, accentable: true) {
                            WidgetSymbol(name: "checkmark", size: 13.5, weight: .bold, color: palette.onacc)
                        }
                    }
                    .accessibilityLabel("Done")
                }
                .buttonStyle(.plain)
            } else if model.state != .clear {
                Button(intent: StartWorkIntent(taskID: taskID, occurrenceID: model.occurrenceID)) {
                    disc(palette.acc, accentable: true) {
                        WidgetSymbol(name: "play.fill", size: 13.5, color: palette.onacc)
                    }
                    .shadow(color: palette.accshadow, radius: 6, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start")
            }
        }
    }

    private func disc(_ fill: Color, accentable: Bool = false, @ViewBuilder _ icon: () -> some View) -> some View {
        ZStack {
            Circle().fill(fill).widgetAccentable(accentable)
            icon().invalidatableContent()
        }
        .frame(width: 32, height: 32)
        .contentShape(Circle())
    }

    private var later: some View {
        VStack(alignment: .leading, spacing: 9) {
            Eyebrow(title: "Later today", color: palette.faint)
            ForEach(model.later) { item in
                HStack(alignment: .center, spacing: 8) {
                    Text(item.time)
                        .css(.mono(10, .medium), line: 1)
                        .foregroundStyle(palette.sub)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 32, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.isMeeting ? palette.track : palette.col(item.accent))
                        .widgetAccentable(!item.isMeeting)
                        .frame(width: 3, height: 15)
                    Text(item.title)
                        .css(.sans(11.5, .medium), line: 1.2)
                        .foregroundStyle(item.isMeeting ? palette.sub : palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
