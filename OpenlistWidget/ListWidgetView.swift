//
//  ListWidgetView.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// One list the user picked, with its progress and tickable tasks.
struct ListWidgetView: View {
    let model: ListModel
    let size: WidgetSize
    let libraryID: UUID?
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.rows.isEmpty {
                AllClearView(subtitle: "Every task in this list is done")
            } else {
                rows
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
            if size == .large {
                // The whole name, as the app's add row gives it: lists have no
                // short form like the design's "Add to Kyoto".
                WidgetFooter(addLabel: "Add to \(model.name)", compactAddLabel: "New task",
                             addURL: WidgetRoute.capture(listID: model.id, forToday: false).url, note: "\(model.done) done")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            glyph
                .frame(width: 28, height: 28)
                .background(palette.tint(model.accent), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.name)
                        .css(.sans(13, .bold), line: 1.1)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text("\(model.open) open")
                        .monospacedDigit()
                        .css(.sans(10.5, .medium), line: 1)
                        .foregroundStyle(palette.sub)
                        .lineLimit(1)
                        .fixedSize()
                }
                ThinBar(progress: model.progress, color: palette.col(model.accent))
            }
        }
    }

    /// The tile's 15 px emoji, or an SF Symbol in the list's colour, as the
    /// app draws one, rather than its name.
    @ViewBuilder private var glyph: some View {
        if ListIcon.isSymbolName(model.emoji) {
            Image(systemName: model.emoji)
                .font(.system(size: 15 * 0.9, weight: .medium))
                .foregroundStyle(palette.col(model.accent))
        } else {
            Text(model.emoji)
                .font(.system(size: EmojiSize.points(forDesign: 15)))
                .grayscale(palette.isDimmed ? 1 : 0)
                .brightness(palette.isDimmed ? 0.25 : 0)
        }
    }

    private var rows: some View {
        let shown = Array(model.rows.prefix(size == .medium ? 3 : 6))
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(shown) { row in
                TaskRowView(row: row, showsMeta: size != .medium, link: WidgetRoute.taskURL(libraryID: libraryID, taskID: row.id))
            }
            if model.rowCount > shown.count { MoreLine(count: model.rowCount - shown.count) }
        }
    }
}
