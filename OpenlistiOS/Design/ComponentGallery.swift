//
//  ComponentGallery.swift
//  OpenlistiOS
//

#if DEBUG
import SwiftUI

/// Every design component (C1–C30 in design-system.md) on one page, for
/// review against the mockups in light and dark. Debug builds only: open it
/// from Settings, or launch with `OpenlistComponentGallery=1`.
struct ComponentGallery: View {
    let close: () -> Void
    @State private var toggle = true
    @State private var estimate = 90
    @State private var segment = 1
    @State private var tab = PhoneTab.today
    @State private var day: Date?
    @State private var search = ""
    @State private var foldOpen = false
    @Environment(\.appClock) private var clock

    var body: some View {
        OLScreen(identifier: "screen.gallery") {
            OLTopBar {
                OLEyebrow("Component gallery")
            } trailing: {
                Button("Done", action: close).buttonStyle(.olLink(strong: true))
            }
        } content: {
            OLHeader("Components", sub: "C1–C30 from design-system.md")
            if page == nil || page == 0 { swatches; rows }
            if page == nil || page == 1 { controls }
            if page == nil || page == 2 { buttons; cards }
            if page == nil || page == 3 { calendarPieces }
            if page == nil || page == 4 { bars }
        }
    }

    /// `OpenlistGalleryPage` 0–4 shows one part, for screenshots of each.
    private var page: Int? {
        ProcessInfo.processInfo.environment["OpenlistGalleryPage"].flatMap(Int.init)
    }

    // MARK: Tokens

    private var swatches: some View {
        OLGroup("Tokens") {
            OLFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Self.tokens, id: \.0) { name, color in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color)
                            .frame(width: 44, height: 32)
                            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(OL.line) }
                        Text(name).font(.system(size: 9)).foregroundStyle(OL.muted)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(OL.Tint.allCases, id: \.self) { tint in
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.color).frame(height: 28)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OL.heat(level)).frame(width: 23, height: 23)
                }
            }
        }
    }

    private static let tokens: [(String, Color)] = [
        ("canvas", OL.canvas), ("surface", OL.surface), ("sunken", OL.sunken), ("line", OL.line),
        ("lineStrong", OL.lineStrong), ("ink", OL.ink), ("muted", OL.muted), ("accent", OL.accent),
        ("accentText", OL.accentText), ("accentSoft", OL.accentSoft), ("today", OL.today), ("todayText", OL.todayText),
        ("danger", OL.danger), ("dangerSoft", OL.dangerSoft), ("info", OL.info), ("success", OL.success),
        ("successText", OL.successText), ("successSoft", OL.successSoft), ("teal", OL.teal), ("amber", OL.amber),
    ]

    // MARK: Rows

    private var rows: some View {
        OLGroup("Task rows · checkbox · trailing") {
            VStack(spacing: 0) {
                OLTaskRow(title: "Close out Q2 retro actions", state: .late, trailing: .text("3d late", tone: .late))
                OLTaskRow(title: "Write interview feedback for Priya", trailing: .text("11:30", tone: .due),
                          separator: .task(nested: false))
                OLTaskRow(title: "Ask Mika to water the planters", trailing: .repeats("Repeats every Wednesday"),
                          separator: .task(nested: false))
                OLTaskRow(title: "Book the ryokan", trailing: .star, separator: .task(nested: false))
                OLTaskRow(title: "Compare Gion vs Arashiyama", state: .done, depth: 1, separator: .task(nested: true))
                OLTaskRow(title: "Renew passports", state: .selected, trailing: .text("Sat"), separator: .task(nested: true),
                          isHighlighted: true)
                OLTaskRow(title: "Reserve the Nishiki market tour", state: .priority(.high), subtitle: "Weekend in Kyoto",
                          trailing: .text("2d late", tone: .late), separator: .task(nested: false))
            }
            .olCard()
            OLFold("done", count: 1, isExpanded: $foldOpen) {
                VStack(spacing: 0) {
                    OLTaskRow(title: "Reply to Kasuga about the tatami room", state: .done, trailing: .text("08:28"))
                }
                .olCard()
            }
            OLLinkRow("done today", count: 2) {}
        }
    }

    // MARK: Controls

    private var controls: some View {
        OLGroup("Chips · segmented · toggle · stepper · field") {
            OLFlowLayout {
                OLChip("Inbox", glyph: "📥", style: .on)
                OLChip("Weekend in Kyoto", glyph: "🗻")
                OLChip("Fri 25, 18:00", small: true, tint: OL.accentText)
                OLChip("#travel", small: true, tint: OL.teal)
                OLChip("Later", style: .ink)
                OLChip("", symbol: "calendar")
                OLChip("#travel", style: .token, tint: OL.teal)
            }
            OLSegmented([(0, "System"), (1, "Monday"), (2, "Sunday")], selection: $segment)
            VStack(spacing: 0) {
                OLSettingsRow("Show done in lists", tile: .accent("checkmark")) {
                    Toggle("Show done in lists", isOn: $toggle).labelsHidden().olToggle()
                }
                OLSettingsRow("Week starts on", tile: .today("calendar"), separator: .settings) { OLRowValue("Monday") }
                OLSettingsRow("Reduce motion", tile: .teal("water.waves"), separator: .settings) { OLRowValue(nil) }
                OLSettingsRow("Calendar access", tile: .info("calendar"), separator: .settings) {
                    OLRowValue("On", color: OL.successText, showsChevron: false)
                }
                OLSettingsRow("Trash", tile: .danger("trash"), separator: .settings) { OLRowValue("3") }
                OLSettingsRow("Estimate", separator: .inset(16)) { OLStepper(value: $estimate) }
            }
            .olCard()
            VStack(spacing: 0) {
                OLFieldRow("When") { Text("Today, 10:00–11:30").foregroundStyle(OL.accentText) }
                OLFieldRow("List", separator: .inset(16)) { Text("💼 Q3 planning") }
            }
            .olCard()
            OLSearchLink {}
            OLSearchField(text: $search, prompt: "Add words or filters") {
                OLChip("#travel", style: .token, tint: OL.teal)
            }
            OLProgressBar(value: 0.44)
            OLProgressBar(value: 1 / 6, tint: OL.info)
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        OLGroup("Buttons · icon buttons · links") {
            Button("Triage one by one") {}.buttonStyle(.ol(.primary, block: true))
            HStack(spacing: 12) {
                Button("Add") {}.buttonStyle(.ol(.primary, size: .small))
                Button("Later") {}.buttonStyle(.ol(.ink, size: .large))
                Button("Cancel") {}.buttonStyle(.olLink())
                Button("Done") {}.buttonStyle(.olLink(strong: true))
            }
            Button("Hold to empty Trash") {}.buttonStyle(.ol(.danger, block: true))
            HStack(spacing: 12) {
                OLIconButton("calendar", label: "Timeline", kind: .bare, iconSize: 22) {}
                OLIconButton("play.fill", label: "Play", kind: .accent, iconSize: 16) {}
                OLIconButton("checkmark", label: "Done", kind: .ok, size: .large) {}
                OLIconButton("trash", label: "Delete", kind: .bad, size: .large) {}
                OLIconButton("trash", label: "Trash", kind: .raised, size: .large) {}
            }
            HStack(spacing: 24) {
                OLIconButton("xmark", label: "Stop", size: .large) {}
                OLIconButton("pause.fill", label: "Pause", kind: .accent, size: .extraLarge) {}
                OLIconButton("checkmark", label: "Done", kind: .success, size: .large) {}
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                OLTile(icon: "🗻", fill: OL.sunken)
                OLTile(icon: "🗻", size: 60, raised: true)
                OLTile(icon: "tray", accent: OL.info, fill: OL.sunken)
                OLCheckbox(.open, size: 28) {}
                OLCheckbox(.done, size: 28) {}
            }
        }
    }

    // MARK: Cards

    private var cards: some View {
        OLGroup("Now card · list cards · empty state") {
            OLNowCard(eyebrow: "Now · 10:00", title: "Draft Q3 OKRs", detail: "50 min left", open: {}, play: {})
            OLListGrid {
                OLListCard(title: "Weekend in Kyoto", icon: "🗻", accent: .violet, detail: "7 open") {}
                OLListCard(title: "Home", icon: "🏡", accent: .green, detail: "3 open") {}
                OLListCard(title: "Hiring loop", icon: "🎯", accent: .pink, detail: "3 open") {}
                OLNewListCard {}
            }
            OLEmptyState(symbol: "sun.max", title: "Today is clear",
                         message: "1 finished today. Nothing is overdue, due, planned or starred.",
                         actionTitle: "Look at tomorrow") {}
                .padding(.vertical, 12)
        }
    }

    // MARK: Calendar

    private var calendarPieces: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today)! }
        return OLGroup("Week strip · timeline") {
            OLWeekStrip(days: OLWeekStrip.week(containing: today, calendar: calendar),
                        selection: Binding(get: { day ?? today }, set: { day = $0 }), today: today, calendar: calendar)
            OLGroupHeader("Schedule") { OLGroupAction("3 to plan") {} }
            OLTimeline(items: [
                .init(id: "a", kind: .done, title: "Standup notes", start: at(9, 15), end: at(9, 45)),
                .init(id: "b", kind: .working, title: "Draft Q3 OKRs", start: at(10), end: at(11, 30), detail: "Now · 50 min left"),
                .init(id: "c", kind: .planned, title: "Write interview feedback for Priya", start: at(11, 31), end: at(11, 50),
                      detail: "20m"),
                .init(id: "d", kind: .event, title: "Design sync", start: at(14), end: at(15)),
                .init(id: "e", kind: .due, title: "Pay the ryokan deposit", start: at(18), end: at(18)),
            ], now: at(10, 40), calendar: calendar)
            .olCard()
        }
    }

    // MARK: Bars

    private var bars: some View {
        OLGroup("Dock · bulk bar · tray · sheet header") {
            OLDock(tab: $tab, inboxCount: 6, capture: {})
                .padding(.horizontal, -OLMetrics.gutter)
            OLBulkBar(actions: [
                .init(symbol: "checkmark", label: "Mark done") {},
                .init(symbol: "sun.max", label: "Move to today") {},
                .init(symbol: "arrow.right", label: "Move to tomorrow") {},
                .init(symbol: "square.grid.2x2", label: "Move to another list") {},
                .init(symbol: "trash", label: "Move to Trash") {},
            ])
            .padding(.horizontal, -OLMetrics.gutter)
            OLTrayView(message: TrayMessage(text: "Restored to Home", seconds: 60, actionTitle: "Undo"), action: {},
                       announces: false)
            VStack(alignment: .leading) {
                OLSheetHeader(confirmTitle: "Add", cancel: {}, confirm: {})
                Text("Buy yen for the trip fri 6pm ~15m #travel").font(OLFont.captureInput)
            }
            .padding(.horizontal, OLMetrics.gutter)
            .padding(.bottom, 16)
            .olCard(radius: 28)
            OLActionDock {
                OLIconButton("trash", label: "Move to Trash", kind: .raised, size: .large) {}
                Button {} label: { Label("Start working", systemImage: "play.fill") }
                    .buttonStyle(.ol(.primary, size: .large, block: true, glows: true))
            }
            .padding(.horizontal, -OLMetrics.gutter)
        }
    }
}

/// Presents the gallery over the shell while the navigator asks for it.
struct ComponentGalleryPresenter: ViewModifier {
    @Environment(PhoneEnvironment.self) private var env

    func body(content: Content) -> some View {
        @Bindable var navigator = env.navigator
        content.fullScreenCover(isPresented: $navigator.showsComponentGallery) {
            ComponentGallery { navigator.showsComponentGallery = false }
                .environment(env)
        }
    }
}
#endif
