//
//  OLScreen.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C1 Screen scaffold

/// A screen's scroll (`.scroll`): the canvas, 20 pt gutters, the top bar just
/// under the status bar, and 40 pt below the last card, above the dock on a
/// tab's page (`olDockRoom`) or else the screen's edge.
///
/// The system navigation bar is hidden: the design draws its top bar in the
/// content, where it scrolls with the page. Swiping back still works
/// (`Platform/SwipeBack.swift`).
struct OLScreen<TopBar: View, Content: View>: View {
    var identifier: String?
    var scrolls = true
    @ViewBuilder var topBar: TopBar
    @ViewBuilder var content: Content
    @Environment(\.olDockRoom) private var dockRoom

    init(identifier: String? = nil, scrolls: Bool = true,
         @ViewBuilder topBar: () -> TopBar, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.scrolls = scrolls
        self.topBar = topBar()
        self.content = content()
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    column
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                column.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .safeAreaPadding(.bottom, dockRoom)
        .background(OL.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .modifier(ScreenIdentifier(identifier: identifier))
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            content
        }
        .foregroundStyle(OL.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, OLMetrics.screenTop)
        .padding(.bottom, OLMetrics.screenBottom)
    }
}

extension OLScreen where TopBar == EmptyView {
    init(identifier: String? = nil, scrolls: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(identifier: identifier, scrolls: scrolls, topBar: { EmptyView() }, content: content)
    }
}

/// The design's layout constants (design-system.css), in points.
enum OLMetrics {
    static let gutter: CGFloat = 20
    /// Between the status bar and the top bar: the mockup's 54 less the
    /// status bar it drew.
    static let screenTop: CGFloat = 6
    /// Below the last card, above the dock (or the screen's bottom edge).
    static let screenBottom: CGFloat = 40
    /// Header to the first card.
    static let headerGap: CGFloat = 20
    static let cardGap: CGFloat = 16
    /// Between groups (`.group`).
    static let groupGap: CGFloat = 24
    static let cardRadius: CGFloat = 20
    /// The dock's bar: 64 high, 28 above the screen's bottom edge.
    static let dockHeight: CGFloat = 64
    static let dockBottom: CGFloat = 28
    /// A tray over a screen's own 56–64 pt bottom bar (Task detail's actions,
    /// Select's bulk bar, Triage's buttons): 12 pt above it.
    static let trayAboveScreenBar: CGFloat = 76
}

extension EnvironmentValues {
    /// How far the dock sits below the bottom safe area's edge: 28 pt above
    /// the screen's, into the home indicator's room. Bars that take the
    /// dock's place (Select's, Task detail's) drop the same way.
    @Entry var olDockDrop: CGFloat = 0
    /// The dock's room over a tab's pages, above the bottom safe area. Set
    /// here rather than as the root's inset, which a tab's navigation stack
    /// doesn't pass on to its scroll views.
    @Entry var olDockRoom: CGFloat = 0
}

private struct ScreenIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

// MARK: - C2 Top bar

/// The 44 pt bar at the top of a screen (`.topbar`): a leading item and
/// trailing buttons. Its items pad 10 pt into the gutter, as the design's
/// −10 margin does, so their text lines up with the content below.
struct OLTopBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 0)
            HStack(spacing: 0) { trailing }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, -10)
    }
}

extension OLTopBar where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}

/// The top bar's date or count (`.eyebrow`), in the colour of what it's about.
struct OLEyebrow: View {
    let text: String
    var color: Color = OL.todayText

    init(_ text: String, color: Color = OL.todayText) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(OLFont.eyebrow)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .contentTransition(.numericText())
    }
}

/// "< Today" (`.back`): the previous screen's title in the accent text.
struct OLBackButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 22, height: 22)
                Text(title)
            }
            .font(OLFont.link)
            .foregroundStyle(OL.accentText)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(OLPressStyle())
        .accessibilityLabel("Back to \(title)")
    }
}

// MARK: - C3 Header

/// A screen's serif title and its line under (`.vt`, `.sub`).
struct OLHeader: View {
    let title: String
    var sub: String?
    /// Above the title, 4 pt; the list page uses 14 under its tile.
    var topSpacing: CGFloat = 4

    init(_ title: String, sub: String? = nil, topSpacing: CGFloat = 4) {
        self.title = title
        self.sub = sub
        self.topSpacing = topSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            OLTitle(title)
            if let sub {
                Text(sub)
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.top, topSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Instrument Serif at 36 on the design's 40 pt line.
struct OLTitle: View {
    let text: String
    var size: CGFloat = 36
    var lineHeight: CGFloat = 40
    var style: Font.TextStyle = .largeTitle
    @ScaledMetric private var scale: CGFloat = 1

    init(_ text: String, size: CGFloat = 36, lineHeight: CGFloat = 40, style: Font.TextStyle = .largeTitle) {
        self.text = text
        self.size = size
        self.lineHeight = lineHeight
        self.style = style
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: style)
    }

    var body: some View {
        let overflow = OLFont.serifOverflow(size: size, lineHeight: lineHeight) * scale
        Text(text)
            .font(OLSerif.font(size: size, relativeTo: style))
            .foregroundStyle(OL.ink)
            .lineLimit(3)
            .padding(.vertical, -overflow)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - C4 Group header, link rows

/// A titled group of cards (`.group`): 24 pt above, the header, 8 pt, then
/// the content.
struct OLGroup<Accessory: View, Content: View>: View {
    let title: String
    var topSpacing: CGFloat = OLMetrics.groupGap
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String, topSpacing: CGFloat = OLMetrics.groupGap,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.topSpacing = topSpacing
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OLGroupHeader(title) { accessory }
            content
        }
        .padding(.top, topSpacing)
    }
}

extension OLGroup where Accessory == EmptyView {
    init(_ title: String, topSpacing: CGFloat = OLMetrics.groupGap, @ViewBuilder content: () -> Content) {
        self.init(title, topSpacing: topSpacing, accessory: { EmptyView() }, content: content)
    }
}

/// `.gh`: 15/20 semibold muted, with an optional trailing action or value.
struct OLGroupHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            accessory
        }
        .font(OLFont.groupHeader)
        .foregroundStyle(OL.muted)
        .frame(minHeight: 20)
        .padding(.horizontal, 4)
    }
}

extension OLGroupHeader where Accessory == EmptyView {
    init(_ title: String) { self.init(title, accessory: { EmptyView() }) }
}

/// A group header's trailing action (`.gh .act`): "3 to plan".
struct OLGroupAction: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        // A 44 pt target that leaves the header its 20 pt line.
        Button(title, action: action)
            .font(OLFont.groupHeader.weight(.medium))
            .foregroundStyle(OL.accentText)
            .buttonStyle(OLPressStyle())
            .padding(.vertical, 12)
            .contentShape(.rect)
            .padding(.vertical, -12)
    }
}

/// A group header that goes somewhere: "2 done today ›", "History ›". The
/// count is a number with a space before its words, as the design sets it.
struct OLLinkRow: View {
    let title: String
    var count: Int?
    var topSpacing: CGFloat = 20
    let action: () -> Void

    init(_ title: String, count: Int? = nil, topSpacing: CGFloat = 20, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.topSpacing = topSpacing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let count {
                    Text("\(count)").contentTransition(.numericText())
                }
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(OLFont.groupHeader)
            .foregroundStyle(OL.muted)
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(OLPressStyle())
        .padding(.top, topSpacing)
        .accessibilityLabel(count.map { "\($0) \(title)" } ?? title)
    }
}

// MARK: - C37 Fold

/// "1 done ›", which shows the done rows under it when open. The chevron
/// turns a quarter over 160 ms.
struct OLFold<Content: View>: View {
    let title: String
    var count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @Environment(\.olStyle) private var style

    init(_ title: String, count: Int? = nil, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        // The card sits right under the 44 pt header, as the design's.
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(style.animation(OLStyle.fold)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(count.map { "\($0) \(title)" } ?? title)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(OLFont.groupHeader)
                .foregroundStyle(OL.muted)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(OLPressStyle())
            .accessibilityLabel(count.map { "\($0) \(title)" } ?? title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded { content }
        }
        .padding(.top, 20)
    }
}
