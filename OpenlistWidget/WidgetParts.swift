//
//  WidgetParts.swift
//  OpenlistWidget
//
//  The pieces the widgets share: the design's Material glyphs, rows and their
//  checkboxes, rings, bars, section heads, the empty state and the footer.
//

import AppIntents
import SwiftUI
import WidgetKit

/// A Material Symbol from the design, drawn as its SF Symbol at the design's size.
struct WidgetSymbol: View {
    let name: String
    let size: CGFloat
    var weight: Font.Weight = .medium
    let color: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }
}

// MARK: - Material glyphs

// The design's Material Symbols Rounded glyphs whose SF Symbols have other
// proportions: SF's checkmark is nearly square and its pause bars sit close,
// where the design's are short and wide, and far apart. Each is drawn on the
// font's 24-unit em square, the size a CSS font size gives it.

/// Maps the font's 24-unit em square onto `rect`, centred.
private nonisolated struct MaterialGrid {
    let rect: CGRect
    var unit: CGFloat { min(rect.width, rect.height) / 24 }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.midX + (x - 12) * unit, y: rect.midY + (y - 12) * unit)
    }
}

/// `check`, which the design sets at weight 700, past the 600 the design
/// loads: the glyph's centre line and stroke as the design renders them,
/// with its round ends.
nonisolated struct MaterialCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = MaterialGrid(rect: rect)
        var line = Path()
        line.move(to: grid.point(6.1, 12.6))
        line.addLine(to: grid.point(9.35, 16.2))
        line.addLine(to: grid.point(17.9, 7.7))
        return line.strokedPath(StrokeStyle(lineWidth: 2.85 * grid.unit, lineCap: .round, lineJoin: .round))
    }
}

/// `play_arrow`, filled: a triangle with rounded corners, a little right of centre.
nonisolated struct MaterialPlay: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = MaterialGrid(rect: rect)
        // The font's own outline, in its 960-unit em square.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { grid.point(x / 40, y / 40) }
        var path = Path()
        path.move(to: p(320, 687))
        path.addLine(to: p(320, 273))
        path.addQuadCurve(to: p(332, 244.5), control: p(320, 256))
        path.addQuadCurve(to: p(360, 233), control: p(344, 233))
        path.addQuadCurve(to: p(370.5, 234.5), control: p(365, 233))
        path.addQuadCurve(to: p(381, 239), control: p(376, 236))
        path.addLine(to: p(707, 446))
        path.addQuadCurve(to: p(720.5, 461), control: p(716, 452))
        path.addQuadCurve(to: p(725, 480), control: p(725, 470))
        path.addQuadCurve(to: p(720.5, 499), control: p(725, 490))
        path.addQuadCurve(to: p(707, 514), control: p(716, 508))
        path.addLine(to: p(381, 721))
        path.addQuadCurve(to: p(370.5, 725.5), control: p(376, 724))
        path.addQuadCurve(to: p(360, 727), control: p(365, 727))
        path.addQuadCurve(to: p(332, 715.5), control: p(344, 727))
        path.addQuadCurve(to: p(320, 687), control: p(320, 704))
        path.closeSubpath()
        return path
    }
}

/// `pause`, filled, at the design's weight 500: two nearly round-ended bars.
nonisolated struct MaterialPause: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = MaterialGrid(rect: rect)
        var path = Path()
        for left in [5.25, 14.0] as [CGFloat] {
            let origin = grid.point(left, 5.35)
            path.addRoundedRect(in: CGRect(x: origin.x, y: origin.y, width: 4.75 * grid.unit, height: 13.3 * grid.unit),
                                cornerSize: CGSize(width: 2.2 * grid.unit, height: 2.2 * grid.unit))
        }
        return path
    }
}

/// A Material glyph at a CSS font size, centred as the design's flex boxes centre it.
struct MaterialGlyph<Glyph: Shape>: View {
    let glyph: Glyph
    let size: CGFloat
    let color: Color

    var body: some View {
        glyph.fill(color).frame(width: size, height: size)
    }
}

/// The design's SVG ring: r = 10 in a 24 viewBox, rotated to start at the top.
struct ProgressRing: View {
    let progress: Double
    let diameter: CGFloat
    /// The stroke width in the 24-unit viewBox.
    let stroke: CGFloat
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let scale = diameter / 24
        let width = stroke * scale
        ZStack {
            Circle().stroke(palette.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(palette.green, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .frame(width: 20 * scale, height: 20 * scale)
        .frame(width: diameter, height: diameter)
    }
}

/// A 3 pt progress bar on the track.
struct ThinBar: View {
    let progress: Double
    let color: Color
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                palette.track
                color
                    .frame(width: proxy.size.width * (max(0, min(1, progress)) * 100).rounded() / 100)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .widgetAccentable()
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// "OVERDUE", "DUE TODAY": 700 9.5 px, tracked, uppercase.
struct SectionHead: View {
    let title: String
    let color: Color
    let isFirst: Bool

    var body: some View {
        Text(title.uppercased())
            .tracking(9.5 * 0.08)
            .css(.sans(9.5, .bold), line: 1)
            .foregroundStyle(color)
            .padding(.top, isFirst ? 2 : 7)
    }
}

/// A small uppercase label: 700 10 px, tracked.
struct Eyebrow: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title.uppercased())
            .tracking(10 * 0.08)
            .css(.sans(10, .bold), line: 1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// A hairline: `border-left:0.5px solid var(--line)`.
struct Hairline: View {
    var vertical = true
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        palette.line.frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

// MARK: - Checkbox

/// The row's circle. The checkbox is a toggle so a tick runs its intent and
/// fills at once; the row itself leaves on the reload that follows. Only the
/// circle is the toggle, so a tap anywhere else in the row can't tick the
/// task: the widget has no undo.
struct CheckToggleStyle: ToggleStyle {
    let ring: Color
    /// Already completed in the snapshot: green. Ticked just now: the design's
    /// closing look, the accent a touch larger.
    let isCompleted: Bool
    let palette: WidgetPalette

    func makeBody(configuration: Configuration) -> some View {
        let filled = configuration.isOn
        let closing = filled && !isCompleted
        ZStack {
            Group {
                if filled {
                    Circle().fill(closing ? palette.acc : palette.green)
                } else {
                    Circle().strokeBorder(ring, lineWidth: 1.5)
                }
            }
            .widgetAccentable()
            MaterialGlyph(glyph: MaterialCheck(), size: 10, color: palette.onacc)
                .opacity(filled ? 1 : 0)
        }
        .frame(width: 15, height: 15)
        .scaleEffect(closing ? 1.12 : 1)
        .contentShape(Circle())
    }
}

struct TaskCheckbox: View {
    let row: WidgetRow
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        Toggle(isOn: row.isDone, intent: SetTaskCompletionIntent(taskID: row.id, occurrenceID: row.occurrenceID)) {
            Text(row.isDone ? "Reopen \(row.title)" : "Complete \(row.title)")
        }
        .toggleStyle(CheckToggleStyle(ring: ring, isCompleted: row.isDone, palette: palette))
    }

    /// Red when late or high priority, amber at medium, else the list's colour.
    private var ring: Color {
        if row.isLate || row.priority == 3 { return palette.red }
        if row.priority == 2 { return palette.amber }
        return palette.col(row.accent)
    }
}

// MARK: - Rows

/// A task line in Today and List (`mkRow` in the design).
struct TaskRowView: View {
    let row: WidgetRow
    /// Small Today: a two-line title with the due text beneath it.
    var compact = false
    var showsMeta = true
    /// Where the title opens: the task, in medium and large widgets.
    var link: URL?
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TaskCheckbox(row: row).padding(.top, 1)
            Group {
                if let link {
                    WidgetLink(destination: link) { text }
                } else {
                    text
                }
                if !compact && row.isStarred {
                    WidgetSymbol(name: "star.fill", size: 8, weight: .regular, color: palette.amber)
                        .frame(width: 11, height: 11)
                        .padding(.top, 2)
                }
                if !compact && !row.dueText.isEmpty {
                    Text(row.dueText)
                        .monospacedDigit()
                        .css(.sans(10, .medium), line: 1.3)
                        .foregroundStyle(row.isLate ? palette.red : palette.sub)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.top, 1)
                }
            }
            // While a tick's intent runs, the system dims the rows beside
            // their circles until the reload takes the ticked one away. The
            // design fades only that row and strikes its title, which would
            // put the row inside the circle's toggle.
            .invalidatableContent()
        }
        .accessibilityElement(children: .combine)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .strikethrough(row.isDone)
                .css(.sans(compact ? 11.5 : 12, .medium), line: 1.3)
                .foregroundStyle(row.isDone ? palette.sub : palette.ink)
                .lineLimit(compact ? 2 : 1)
                .truncationMode(.tail)
            if showsMeta {
                meta
                    .css(.sans(10, .medium), line: 1.2)
                    .foregroundStyle(compact && row.isLate ? palette.red : palette.solid)
                    .opacity(compact && row.isLate ? 1 : palette.faintOpacity)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The list, or in small Today the due text when there is one.
    private var meta: Text {
        if compact && !row.dueText.isEmpty { return Text(row.dueText) }
        return Text(listIcon: palette.isDimmed ? "" : row.listIcon, name: row.listName, size: 10)
    }
}

extension Text {
    /// "🗻 Weekend in Kyoto" on a line set at `size`: the emoji as large as the
    /// design draws it there, not Core Text's larger one (`EmojiSize`).
    init(listIcon icon: String, name: String, size: CGFloat) {
        guard !icon.isEmpty else {
            self.init(verbatim: name)
            return
        }
        let glyph = Text(verbatim: icon).font(.system(size: EmojiSize.points(forDesign: size)))
        self.init("\(glyph) \(name)")
    }
}

/// "+3 more", under the rows.
struct MoreLine: View {
    let count: Int
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        Text("+\(count) more")
            .css(.sans(10.5, .medium), line: 1)
            .foregroundStyle(palette.faint)
            .padding(.leading, 23)
    }
}

// MARK: - Empty and unavailable

/// "All clear": the green disc, the serif title and a line beneath.
struct AllClearView: View {
    let subtitle: String
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        VStack(spacing: 6) {
            Circle().fill(palette.green)
                .widgetAccentable()
                .frame(width: 30, height: 30)
                .overlay { MaterialGlyph(glyph: MaterialCheck(), size: 18, color: palette.onacc) }
            Text("All clear")
                .css(.serif(21), line: 1)
                .foregroundStyle(palette.ink)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .css(.sans(10.5, .medium), line: 1.3)
                .foregroundStyle(palette.sub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown until the app has published anything the widget can read.
struct OpenOpenlistView: View {
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        Text("Open Openlist")
            .multilineTextAlignment(.center)
            .css(.sans(11, .medium), line: 1.4)
            .foregroundStyle(palette.faint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer

/// The large sizes' footer: an add chip and a count.
struct WidgetFooter: View {
    let addLabel: String
    let addURL: URL
    let note: String
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Hairline(vertical: false)
            HStack(alignment: .center, spacing: 8) {
                WidgetLink(destination: addURL) {
                    HStack(spacing: 5) {
                        WidgetSymbol(name: "plus", size: 11, weight: .medium, color: palette.acc)
                            .frame(width: 14, height: 14)
                        Text(addLabel)
                            .css(.sans(11, .semibold), line: 1)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                    }
                    .padding(EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 9))
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer(minLength: 0)
                Text(note)
                    .css(.sans(10.5, .medium), line: 1)
                    .foregroundStyle(palette.sub)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.top, 9)
        }
    }
}
