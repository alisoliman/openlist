//
//  main.swift
//  WidgetPreviews
//
//  Renders every widget kind and size from the design's sample data, in light,
//  dark and the desktop's in-background rendering, so they can be compared with
//  the design (docs/design/openlist-next-v2/widgets). Built and run by
//  Tools/WidgetPreviews/render.sh; not part of Tools/check.sh.
//
//    render.sh [--out DIR] [--fixture default|session|all] [--scale 2]
//

import AppKit
import CoreText
import SwiftUI
import WidgetKit

@main
struct WidgetPreviews {
    static func main() {
        var out = URL(fileURLWithPath: "/tmp/widget-previews")
        var fixtures = WidgetSampleData.Fixture.allCases
        var scale: CGFloat = 2
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--out": out = URL(fileURLWithPath: arguments.next() ?? out.path)
            case "--fixture":
                let value = arguments.next() ?? "all"
                if let fixture = WidgetSampleData.Fixture(rawValue: value) { fixtures = [fixture] }
            case "--scale": scale = CGFloat(Double(arguments.next() ?? "2") ?? 2)
            case "--font": registerFont(URL(fileURLWithPath: arguments.next() ?? ""))
            default: break
            }
        }
        for fixture in fixtures {
            let snapshot = WidgetSampleData.snapshot(fixture: fixture)
            let entry = WidgetEntry(date: WidgetSampleData.referenceDate, snapshot: snapshot)
            for mode in WidgetPalette.Mode.allCases {
                let folder = out.appendingPathComponent("\(fixture.rawValue)/\(mode.rawValue)", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for kind in OpenlistWidgetKind.allCases {
                    for size in kind.sizes {
                        let view = PreviewTile(kind: kind, entry: entry, size: size, mode: mode, framed: true)
                        write(view, size: tileSize(size), scale: scale, to: folder.appendingPathComponent("\(name(kind))-\(size.rawValue).png"))
                    }
                }
                let sheet = PreviewSheet(entry: entry, mode: mode, fixture: fixture)
                write(sheet, size: sheet.size, scale: scale, to: out.appendingPathComponent("\(fixture.rawValue)/\(mode.rawValue)-sheet.png"))
            }
        }
        print("Wrote previews to \(out.path)")
    }

    /// The design's kind names, for the file names.
    static func name(_ kind: OpenlistWidgetKind) -> String {
        switch kind {
        case .today: "today"
        case .upNext: "upnext"
        case .capture: "capture"
        case .list: "list"
        case .agenda: "agenda"
        case .summary: "summary"
        case .activity: "activity"
        }
    }

    /// The widget with 30 points around it, as the reference captures.
    static func tileSize(_ size: WidgetSize) -> CGSize {
        CGSize(width: size.designSize.width + 60, height: size.designSize.height + 60)
    }

    static func registerFont(_ url: URL) {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    @MainActor static func write(_ view: some View, size: CGSize, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("Could not render \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
    }
}

/// One widget as the system would draw it: its rounded background and the
/// design's shadow, on a flat backdrop matching the reference captures.
struct PreviewTile: View {
    let kind: OpenlistWidgetKind
    let entry: WidgetEntry
    let size: WidgetSize
    let mode: WidgetPalette.Mode
    /// Adds the 30-point margin and backdrop.
    var framed = false

    var body: some View {
        let palette = WidgetPalette(mode)
        let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
        let widget = OpenlistWidgetContent(kind: kind, entry: entry, size: size)
            .environment(\.colorScheme, mode == .dark ? .dark : .light)
            .environment(\.widgetRenderingMode, mode == .dimmed ? .vibrant : .fullColor)
            .environment(\.widgetIsPreview, true)
            .frame(width: size.designSize.width, height: size.designSize.height)
            .background { shape.fill(palette.bg) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(outline, lineWidth: 0.5).padding(-0.5) }
            .background {
                if mode != .dimmed {
                    shape.fill(Color.black.opacity(0.001))
                        .shadow(color: mode == .dark ? .black.opacity(0.35) : Color(red: 40 / 255, green: 30 / 255, blue: 20 / 255).opacity(0.14),
                                radius: mode == .dark ? 15 : 14, y: mode == .dark ? 12 : 10)
                }
            }
        if framed {
            widget.frame(maxWidth: .infinity, maxHeight: .infinity).background(backdrop)
        } else {
            widget
        }
    }

    private var outline: Color {
        switch mode {
        case .light: .black.opacity(0.05)
        case .dark: .white.opacity(0.08)
        case .dimmed: .white.opacity(0.3)
        }
    }

    private var backdrop: Color {
        switch mode {
        case .light: Color(hex: 0xD8D2D4)
        case .dark: Color(hex: 0x2A2730)
        case .dimmed: Color(hex: 0x6E6880)
        }
    }
}

/// Every kind on the design's desktop, in its default arrangement; the session
/// fixture repeats the screenshots' row of Up Next small, Up Next medium and Today medium.
struct PreviewSheet: View {
    let entry: WidgetEntry
    let mode: WidgetPalette.Mode
    let fixture: WidgetSampleData.Fixture

    /// Column, row and size on the design's 170-point grid with 18-point gaps.
    private var layout: [(OpenlistWidgetKind, WidgetSize, Int, Int)] {
        fixture == .session
            ? [(.upNext, .small, 0, 0), (.upNext, .medium, 1, 0), (.today, .medium, 3, 0)]
            : [(.today, .large, 0, 0), (.upNext, .medium, 2, 0), (.capture, .small, 4, 0), (.summary, .small, 5, 0),
               (.agenda, .large, 2, 1), (.list, .medium, 4, 1), (.activity, .medium, 0, 2)]
    }

    var size: CGSize {
        CGSize(width: 1400, height: fixture == .session ? 260 : 30 + 3 * 170 + 2 * 18 + 40)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                // radial-gradient(120% 90% at 20% 0%, …)
                let stops = gradient
                let rx = size.width * 1.2, ry = size.height * 0.9
                context.scaleBy(x: rx / ry, y: 1)
                let center = CGPoint(x: size.width * 0.2 * ry / rx, y: 0)
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width * ry / rx, height: size.height)),
                             with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: ry))
            }
            ForEach(layout.indices, id: \.self) { index in
                let (kind, size, column, row) = layout[index]
                PreviewTile(kind: kind, entry: entry, size: size, mode: mode)
                    .offset(x: 30 + CGFloat(column) * 188, y: 30 + CGFloat(row) * 188)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var gradient: [Gradient.Stop] {
        let colors: [UInt32] = switch mode {
        case .light: [0xE6DFD5, 0xCBC4CF, 0xA9A8BC]
        case .dark: [0x3A3546, 0x211F28, 0x15141A]
        case .dimmed: [0x9A92A6, 0x6E6880, 0x4E4A5E]
        }
        return [.init(color: Color(hex: colors[0]), location: 0), .init(color: Color(hex: colors[1]), location: 0.55),
                .init(color: Color(hex: colors[2]), location: 1)]
    }
}
