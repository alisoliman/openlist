//
//  CaptureWidgetView.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// One click to capture. Widgets can't hold a text field, so the tile opens
/// Quick Add; medium adds what's waiting in Inbox and a way into triage.
struct CaptureWidgetView: View {
    let model: CaptureModel
    let size: WidgetSize
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if size == .medium {
                WidgetLink(destination: WidgetRoute.capture(listID: nil, forToday: false).url) {
                    main.frame(width: 118, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 0) {
                    Hairline()
                    inbox.padding(.leading, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                main.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 15)
                .fill(palette.acc)
                .widgetAccentable()
                .frame(width: 46, height: 46)
                .overlay { WidgetSymbol(name: "plus", size: 20, weight: .medium, color: palette.onacc) }
                .shadow(color: palette.accshadow, radius: 9, y: 8)
            Spacer(minLength: 0)
            Text("New task")
                .css(.sans(14, .semibold), line: 1.2)
                .foregroundStyle(palette.ink)
            // A hair tighter at medium size: the system face sets the first
            // line a point wider than the design's 118 pt column, which would
            // wrap the line onto a third and lift "New task" with it.
            Text(size == .small ? "\(model.count) waiting in Inbox" : "Type it, Openlist sorts dates and labels")
                .tracking(size == .small ? 0 : -0.1)
                .css(.sans(11, .medium), line: 1.35)
                .foregroundStyle(palette.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 6) {
                WidgetSymbol(name: "tray.fill", size: 10.5, weight: .regular, color: palette.blue)
                    .frame(width: 13, height: 13)
                Text("Inbox")
                    .css(.sans(12, .bold), line: 1)
                    .foregroundStyle(palette.ink)
                Text("\(model.count)")
                    .css(.sans(11, .medium), line: 1)
                    .foregroundStyle(palette.sub)
                Spacer(minLength: 0)
                WidgetLink(destination: WidgetRoute.triage.url) {
                    Text("Triage")
                        .css(.sans(10.5, .semibold), line: 1)
                        .foregroundStyle(palette.blue)
                        .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        .background(palette.bluechip, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            ForEach(model.items) { item in
                HStack(alignment: .center, spacing: 8) {
                    Circle().fill(palette.faint).frame(width: 5, height: 5)
                    Text(item.title)
                        .css(.sans(11.5, .medium), line: 1.3)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.age)
                        .css(.sans(10, .medium), line: 1)
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
