//
//  main.swift
//  Widget render harness
//
//  Draws widget views the way the desktop shows them, at the design's sizes
//  for comparing with its crops and at the smaller sizes macOS measures.
//  Usage: widget-render <output-dir> <font.ttf> [design|real]
//

import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

let arguments = CommandLine.arguments
/// Both sizes unless the third argument picks one.
let canvases: [RenderCanvas]? = switch arguments.count {
case 3: RenderCanvas.allCases
case 4 where arguments[3] == "design": [.design]
case 4 where arguments[3] == "real": [.measured]
default: nil
}
guard let canvases else {
    FileHandle.standardError.write(Data("usage: widget-render <output-dir> <font.ttf> [design|real]\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
WidgetFonts.register(url: URL(fileURLWithPath: arguments[2]))
guard WidgetFonts.hasSerif else {
    FileHandle.standardError.write(Data("Instrument Serif did not register from \(arguments[2])\n".utf8))
    exit(1)
}

var cases: [RenderCase] = []
#if RENDER_TODAY
cases += TodayWidget.renderCases
#endif
#if RENDER_UPNEXT
cases += UpNextWidget.renderCases
#endif
#if RENDER_QUICKADD
cases += QuickAddWidget.renderCases
#endif
#if RENDER_LIST
cases += ListWidget.renderCases
#endif
#if RENDER_AGENDA
cases += AgendaWidget.renderCases
#endif
#if RENDER_SUMMARY
cases += SummaryWidget.renderCases
#endif
#if RENDER_ACTIVITY
cases += ActivityWidget.renderCases
#endif

/// The mockup's desktop behind a widget, with the 10-point margin the design
/// crops have.
struct Desktop: View {
    let renderCase: RenderCase
    let mode: WidgetStyle.Mode
    let size: CGSize

    var body: some View {
        let family = renderCase.family
        let style = WidgetStyle(mode: mode, accentHex: renderCase.entry.snapshot.accentHex, serifTitles: renderCase.entry.snapshot.serifTitles)
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
        WidgetCanvas(family: family, style: style) {
            renderCase.draw(renderCase.entry, family, style)
        }
        .frame(width: size.width, height: size.height)
        .background(style.bg, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ring, lineWidth: 0.5))
        // One shadow for the whole plate, not one per text run and cell.
        .compositingGroup()
        .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
        .padding(10)
        .background(backdrop)
        .environment(\.colorScheme, mode == .light ? .light : .dark)
    }

    private var ring: Color {
        switch mode {
        case .light: .black.opacity(0.05)
        case .dark: .white.opacity(0.08)
        case .vibrant: .white.opacity(0.3)
        }
    }

    private var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        switch mode {
        case .light: (WidgetStyle.rgb(0x281E14, 0.14), 14, 10)
        case .dark: (.black.opacity(0.35), 15, 12)
        case .vibrant: (.clear, 0, 0)
        }
    }

    private var backdrop: some View {
        let stops: [UInt32] = switch mode {
        case .light: [0xE6DFD5, 0xCBC4CF, 0xA9A8BC]
        case .dark: [0x3A3546, 0x211F28, 0x15141A]
        case .vibrant: [0x9A92A6, 0x6E6880, 0x4E4A5E]
        }
        return EllipticalGradient(
            stops: [.init(color: WidgetStyle.rgb(stops[0]), location: 0),
                    .init(color: WidgetStyle.rgb(stops[1]), location: 0.55),
                    .init(color: WidgetStyle.rgb(stops[2]), location: 1)],
            center: UnitPoint(x: 0.2, y: 0),
            startRadiusFraction: 0,
            endRadiusFraction: 1.2
        )
    }
}

func write(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var failures = 0
for canvas in canvases {
    for renderCase in cases {
        for mode in WidgetStyle.Mode.allCases {
            let name = renderCase.name(canvas: canvas)
            let file = output.appendingPathComponent("\(name)-\(mode == .vibrant ? "dimmed" : mode.rawValue).png")
            let desktop = Desktop(renderCase: renderCase, mode: mode, size: canvas.size(for: renderCase.family))
            let renderer = ImageRenderer(content: desktop)
            renderer.scale = 2
            if let image = renderer.cgImage, write(image, to: file) {
                print(file.path)
            } else {
                FileHandle.standardError.write(Data("Could not render \(file.lastPathComponent)\n".utf8))
                failures += 1
            }
        }
    }
}
if cases.isEmpty { FileHandle.standardError.write(Data("No render cases compiled in\n".utf8)) }
exit(failures == 0 && !cases.isEmpty ? 0 : 1)
