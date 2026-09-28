//
//  CaptureScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// The Capture sheet (mockup 06): a field that tints the date, time, repeat,
/// estimate, priority and labels as they're typed, chips for what Add saves,
/// and the list it goes to. Add saves it at once, with Undo in the tray.
struct CaptureScreen: View {
    let request: CaptureRequest
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @State private var text = ""
    @State private var listID: UUID?
    @State private var height: CGFloat = 236
    @FocusState private var isFocused: Bool

    init(request: CaptureRequest) {
        self.request = request
        _listID = State(initialValue: request.listID)
        #if DEBUG
        // A review session's `OpenlistCaptureText`, typed in for a screenshot.
        if ReviewSession.identifier != nil, let typed = ProcessInfo.processInfo.environment["OpenlistCaptureText"] {
            _text = State(initialValue: typed)
        }
        #endif
    }

    var body: some View {
        let parse = CaptureParse(text, parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now)
        let snapshot = snapshot(parse)
        VStack(alignment: .leading, spacing: 0) {
            OLSheetHeader(confirmTitle: "Add", canConfirm: !parse.title.isEmpty, cancel: { env.navigator.dismissSheet() },
                          confirm: { add(snapshot) })
            field(parse)
                .padding(.top, 10)
            let chips = chips(parse, snapshot: snapshot)
            if !chips.isEmpty {
                OLFlowLayout {
                    ForEach(chips, id: \.label) { chip in chip }
                }
                .padding(.top, 14)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Saves as \(chips.map(\.label).joined(separator: ", "))")
            }
            destinations
                .padding(.top, 16)
        }
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .presentationDetents([.height(height)])
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New task")
        .accessibilityIdentifier(PhoneRoute.capture(request).screenIdentifier)
        .onAppear { isFocused = true }
    }

    // MARK: Field

    /// The typed text drawn tinted under a clear field that takes the typing,
    /// as the Mac's capture card does, so the tokens show where they are.
    private func field(_ parse: CaptureParse) -> some View {
        ZStack(alignment: .topLeading) {
            tinted(parse)
                .accessibilityHidden(true)
            TextField("New task", text: $text, prompt: Text("New task").foregroundStyle(OL.muted), axis: .vertical)
                .font(OLFont.captureInput)
                .foregroundStyle(text.isEmpty ? OL.ink : .clear)
                .tint(OL.accent)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { add(snapshot(parse)) }
                .accessibilityIdentifier("capture.field")
        }
    }

    private func tinted(_ parse: CaptureParse) -> Text {
        var text = AttributedString()
        for segment in parse.segments {
            var run = AttributedString(segment.text)
            if let kind = segment.kind {
                let tone = Self.tone(kind)
                run.foregroundColor = tone
                run.underlineStyle = Text.LineStyle(pattern: .solid, color: tone)
            } else {
                run.foregroundColor = OL.ink
            }
            text += run
        }
        return Text(text).font(OLFont.captureInput)
    }

    static func tone(_ kind: CaptureParse.Kind) -> Color {
        switch kind {
        case .date, .time, .repeatRule: OL.accentText
        case .estimate: OL.muted
        case .label: OL.teal
        case .priority: OL.danger
        }
    }

    // MARK: What Add saves

    /// The parse as Add saves it, due today when the request is for today and
    /// nothing else is typed.
    private func snapshot(_ parse: CaptureParse) -> CaptureSnapshot {
        var snapshot = parse.snapshot()
        if snapshot.date == nil, request.dueToday { snapshot.date = env.settings.calendar.startOfDay(for: env.now) }
        return snapshot
    }

    /// One chip per thing saved, in the order typed: the day and time as one,
    /// "15 min", "#travel". A day nobody typed, today's, comes first.
    private func chips(_ parse: CaptureParse, snapshot: CaptureSnapshot) -> [OLChip] {
        var chips: [OLChip] = []
        var showsWhen = false
        func when() {
            guard !showsWhen, let date = snapshot.date else { return }
            chips.append(OLChip(CompactText.captureWhen(date, includesTime: snapshot.includesTime, now: env.now,
                                                        calendar: env.settings.calendar),
                                small: true, tint: OL.accentText))
            showsWhen = true
        }
        for mark in parse.marks {
            switch mark.kind {
            case .date, .time: when()
            case .repeatRule:
                when()
                if let rule = snapshot.recurrence { chips.append(OLChip(rule.displayText, symbol: "repeat", small: true, tint: OL.accentText)) }
            case .estimate:
                if snapshot.estimateMinutes > 0, !chips.contains(where: { $0.label.hasSuffix(" min") }) {
                    chips.append(OLChip(CompactText.estimate(snapshot.estimateMinutes), small: true))
                }
            case .priority:
                if snapshot.priority != .none, !chips.contains(where: { $0.label == snapshot.priority.title }) {
                    chips.append(OLChip(snapshot.priority.title, symbol: "exclamationmark", small: true, tint: OL.danger))
                }
            case .label:
                let name = "#" + String(mark.raw.dropFirst()).lowercased()
                if !chips.contains(where: { $0.label == name }) { chips.append(OLChip(name, small: true, tint: OL.teal)) }
            }
        }
        if !showsWhen, let date = snapshot.date {
            chips.insert(OLChip(CompactText.captureWhen(date, includesTime: snapshot.includesTime, now: env.now,
                                                        calendar: env.settings.calendar),
                                small: true, tint: OL.accentText), at: 0)
        }
        return chips
    }

    // MARK: Destinations

    private var destinations: some View {
        let chosen = destination?.id
        return OLChipScroller {
            ForEach(library.lists) { list in
                OLChipButton(OLChip(list.displayTitle, glyph: list.isSystemInbox ? "📥" : list.icon,
                                    style: list.id == chosen ? .on : .plain)) {
                    listID = list.id
                }
                .accessibilityAddTraits(list.id == chosen ? .isSelected : [])
            }
        }
    }

    /// The list Add saves into: the one picked, else the Inbox, which also
    /// takes what's captured on an archived list's page.
    private var destination: TaskList? {
        library.lists.first { $0.id == listID } ?? library.inbox
    }

    private func add(_ snapshot: CaptureSnapshot) {
        guard !snapshot.title.isEmpty else { return }
        do {
            let block = try env.store.saveCapture(snapshot, destinationID: destination?.id)
            env.actions.reportCapture(block)
            env.navigator.dismissSheet()
        } catch {
            env.tray.show("Task wasn’t added. \(error.localizedDescription)", icon: "exclamationmark.circle",
                          tone: .danger, seconds: 5)
            env.haptics.play(.error)
        }
    }
}
