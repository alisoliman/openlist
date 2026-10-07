//
//  NextOverlays.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

/// What the overlays and the key monitor share: the search session behind the
/// search card, and the keyboard focus to hand back once the last overlay closes.
@Observable @MainActor
final class NXOverlayState {
    @ObservationIgnored let search = SearchSession()
    /// Why the chosen result can't open, shown until the search changes.
    var searchUnavailable: String?
    /// The search Return was pressed on before its results arrived, with no
    /// listed row chosen: its first result opens once it's in.
    @ObservationIgnored var pendingSearchOpen: SearchOptions?
    /// The shell's key-handling view, whose window the overlays borrow focus from.
    @ObservationIgnored weak var host: NSView?
    /// The sidebar's frame in the window, which the shell reports: the
    /// overlays dim only the main pane, so a field there is never theirs.
    @ObservationIgnored var sidebarFrame: CGRect = .zero
    @ObservationIgnored private weak var returnView: NSView?
    @ObservationIgnored private var returnRange: NSRange?
    @ObservationIgnored private var activation = 0
    @ObservationIgnored private var rememberedActivation = 0

    /// A command or result is about to navigate or inspect a task, so the
    /// caret must not jump back into a field that is being replaced.
    func willNavigate() { activation &+= 1 }

    /// Notes the first responder as the first overlay opens. A text field's
    /// responder is the window's shared field editor, which the overlay's own
    /// field is about to borrow, so the field it edits is kept instead.
    func rememberFocus() {
        guard let window = host?.window else { return }
        let responder = window.firstResponder
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            returnView = editor.delegate as? NSView
        } else {
            returnView = responder as? NSView
        }
        returnRange = (responder as? NSTextView)?.selectedRange()
        rememberedActivation = activation
    }

    /// Whether the window's field editor is editing a field in the sidebar,
    /// such as a list's or section's name, rather than one in the main pane.
    func editsSidebarField() -> Bool {
        guard sidebarFrame.width > 0, let window = host?.window,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSView else { return false }
        let x = field.convert(field.bounds, to: nil).midX
        return x >= sidebarFrame.minX && x <= sidebarFrame.maxX
    }

    /// Returns focus to the remembered view and selection when the overlay
    /// closed in place; otherwise to the window, so the shell gets the keys.
    func restoreFocus() {
        defer {
            returnView = nil
            returnRange = nil
        }
        guard let window = host?.window else { return }
        guard rememberedActivation == activation, let view = returnView, view.window === window,
              window.makeFirstResponder(view) else {
            window.makeFirstResponder(nil)
            return
        }
        let text = view as? NSTextView ?? (view as? NSControl)?.currentEditor() as? NSTextView
        if let text, let range = returnRange, NSMaxRange(range) <= (text.string as NSString).length {
            text.setSelectedRange(range)
        }
    }
}

/// Capture, search and the command palette. Only one shows at a time; the
/// key monitor drives their arrows, Return, Tab and Escape.
struct NextOverlays: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let overlays: NXOverlayState

    var body: some View {
        let workbench = env.workbench
        let navigator = env.navigator
        ZStack(alignment: .top) {
            if workbench.captureOpen {
                NXOverlayBackdrop(top: 96, close: { workbench.closeCapture(keepsDraft: true) }) {
                    NXCaptureCard(draft: workbench, notice: workbench.captureNotice, voice: workbench.voice,
                                  onVoiceSave: { [weak workbench] in workbench?.completeCapture($0, keepOpen: false) },
                                  add: { _ = workbench.createFromCapture(keepOpen: $0) })
                        .animation(style.ease(140), value: workbench.captureNotice)
                        .onChange(of: workbench.captureText) {
                            if workbench.captureNotice != nil { workbench.captureNotice = nil }
                        }
                }
            } else if navigator.isSearchOpen {
                NXOverlayBackdrop(top: 72, close: { navigator.isSearchOpen = false }) {
                    NXSearchCard(overlays: overlays)
                }
            } else if navigator.isCommandPaletteOpen {
                NXOverlayBackdrop(top: 84, close: { navigator.isCommandPaletteOpen = false }) {
                    NXPaletteCard(overlays: overlays)
                }
            }
        }
        // The design's fadeIn and popIn play at their own speeds whatever the
        // Motion setting, which paces only rows, screens and the inspector.
        .animation(NX.cssEase(140), value: workbench.captureOpen)
        .animation(NX.cssEase(140), value: navigator.isSearchOpen)
        .animation(NX.cssEase(140), value: navigator.isCommandPaletteOpen)
        // Switching straight from one overlay to another keeps the first
        // remembered responder: the flags only all drop on the final close.
        .onChange(of: workbench.captureOpen || navigator.isSearchOpen || navigator.isCommandPaletteOpen) { wasOpen, isOpen in
            if isOpen && !wasOpen { overlays.rememberFocus() }
            if wasOpen && !isOpen { overlays.restoreFocus() }
        }
        .onChange(of: navigator.isCommandPaletteOpen) { _, isOpen in
            guard isOpen else { return }
            if workbench.gPressedAt != nil { workbench.endGoChord() }
            workbench.paletteQuery = ""
            workbench.paletteIndex = 0
            navigator.isSearchOpen = false
            if workbench.captureOpen { workbench.closeCapture(keepsDraft: true) }
        }
        .onChange(of: navigator.isSearchOpen) { _, isOpen in
            guard isOpen else { return }
            if workbench.gPressedAt != nil { workbench.endGoChord() }
            workbench.searchQuery = ""
            workbench.searchIndex = 0
            workbench.searchIncludesCompleted = false
            navigator.isCommandPaletteOpen = false
            if workbench.captureOpen { workbench.closeCapture(keepsDraft: true) }
        }
    }
}

/// The dim backdrop (click closes) and the popping card.
private struct NXOverlayBackdrop<Card: View>: View {
    @Environment(\.nextStyle) private var style
    let top: CGFloat
    let close: () -> Void
    @ViewBuilder var card: () -> Card
    @State private var shown = false

    var body: some View {
        // The design's popIn; with Reduce Motion the card only fades.
        let settled = shown || !style.slides
        ZStack(alignment: .top) {
            Color(hex: 0x17161A, opacity: 0.16)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            card()
                .nxOverlayCard()
                .padding(.horizontal, 20)
                .padding(.top, top)
                .scaleEffect(settled ? 1 : 0.97, anchor: .top)
                .offset(y: settled ? 0 : -4)
                .opacity(shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The design's fadeIn as it opens; closed, it goes at once, card and all.
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
        .onAppear { withAnimation(NX.ease(180)) { shown = true } }
    }
}

extension View {
    /// The overlay card's surface: the design's 14pt card with its hairline and
    /// `0 30px 70px` drop, in the window's overlays and the Quick Add panel alike.
    func nxOverlayCard() -> some View {
        background(NX.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NX.ink(0.18), lineWidth: 0.5))
            .shadow(color: Color(hex: 0x17161A, opacity: 0.3), radius: 35, y: 30)
    }
}

/// Puts the caret in an overlay's field once it is on screen.
private struct NXAutofocus: ViewModifier {
    @FocusState private var focused: Bool
    var refocus: AnyHashable = 0
    /// Puts the caret after the text a task heard by voice filled the field
    /// with, where focusing a field selects all of it.
    var caretAtEnd = false

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onAppear {
                DispatchQueue.main.async {
                    focused = true
                    guard caretAtEnd else { return }
                    // Once the field has made its own selection.
                    DispatchQueue.main.async {
                        // Quick Add's panel is key without making Openlist active.
                        let window = NSApp.windows.first(where: \.isKeyWindow)
                        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
                        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                    }
                }
            }
            .onChange(of: refocus) { _, _ in focused = true }
    }
}

/// Reports how far the field editor over this view has scrolled its line
/// sideways, which it does to keep the caret in view once the text is wider
/// than the field, so a copy drawn over the field can follow it.
private struct NXFieldScroll: NSViewRepresentable {
    let changed: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollReader {
        let view = ScrollReader()
        view.changed = changed
        return view
    }

    func updateNSView(_ nsView: ScrollReader, context: Context) {
        nsView.changed = changed
    }

    final class ScrollReader: NSView {
        var changed: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var offset: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard window != nil else { return }
            let center = NotificationCenter.default
            // The field editor's clip view moves its bounds as it scrolls.
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: nil,
                                                queue: .main) { [weak self] note in
                // Delivered on the main queue; only the posting object crosses in.
                nonisolated(unsafe) let object = note.object
                MainActor.assumeIsolated {
                    guard let self, let clip = object as? NSClipView, clip.window === self.window,
                          let editor = clip.documentView as? NSTextView, editor.isFieldEditor,
                          let field = editor.delegate as? NSTextField, self.covers(field) else { return }
                    self.report(clip.bounds.minX)
                }
            })
            // Once it stops editing, the field draws its text from the start again.
            observers.append(center.addObserver(forName: NSControl.textDidEndEditingNotification, object: nil,
                                                queue: .main) { [weak self] note in
                nonisolated(unsafe) let object = note.object
                MainActor.assumeIsolated {
                    guard let self, let field = object as? NSTextField, self.covers(field) else { return }
                    self.report(0)
                }
            })
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        private func covers(_ field: NSTextField) -> Bool {
            guard let window, field.window === window else { return false }
            return field.convert(field.bounds, to: nil).intersects(convert(bounds, to: nil))
        }

        private func report(_ x: CGFloat) {
            let x = max(0, x)
            guard x != offset else { return }
            offset = x
            changed?(x)
        }
    }
}

// MARK: - Capture

// The draft a capture card types into (`NXCaptureDraft`) and what saving it
// makes of it are UI-free and shared with the phone (CaptureDraft.swift).

/// The main window's capture, which `openCapture` fills for the current screen.
extension Workbench: NXCaptureDraft {}

/// The design's capture card, over the main window or in the Quick Add panel.
/// Its host handles Return, Tab and Escape; `add` is what Return and ⇧↩ do,
/// offered to assistive technologies as the field's actions. With `voice`,
/// a mic at the field's end listens for tasks said instead of typed: the
/// card shows what it hears, then one task in the field or several as rows.
struct NXCaptureCard<Draft: NXCaptureDraft>: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    @Bindable var draft: Draft
    var notice: NXCaptureNotice?
    var voice: VoiceCapture?
    var managesVoiceLifecycle = true
    var onVoiceSave: ((NXCaptureOutcome) -> Void)?
    var undoCapture: (() -> Void)?
    var add: ((_ keepOpen: Bool) -> Void)?
    @State private var refocus = 0
    /// How far the field has scrolled its text to keep the caret in view.
    @State private var scroll: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let voice, voice.isActive {
                NXVoicePanel(voice: voice, stop: toggleVoice)
            } else if !draft.spokenTasks.isEmpty {
                heard
            } else {
                typing(draft.captureParse())
            }

            if let failure = voiceFailure {
                NXVoiceFailureLine(failure: failure)
                    .padding(EdgeInsets(top: 0, leading: 46, bottom: 12, trailing: 18))
                    .transition(.opacity)
            } else if let notice, notice.failed {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10.5, weight: .semibold))
                    Text(notice.text).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NX.redText)
                .padding(EdgeInsets(top: 0, leading: 46, bottom: 12, trailing: 18))
                .transition(.opacity)
            }

            destinations
                .padding(.vertical, 10)
                .background(NX.ink(0.02))
                .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
        }
        .frame(maxWidth: 600)
        .onChange(of: draft.captureText) { voice?.dismissFailure() }
        .onDisappear { if managesVoiceLifecycle { voice?.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if managesVoiceLifecycle { voice?.applicationResignedActive() }
        }
    }

    /// The field and the chips for what it saves.
    @ViewBuilder private func typing(_ parse: CaptureParse) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .strokeBorder(NX.ink(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [2.6, 2.2]))
                .frame(width: 17, height: 17)
                .padding(.top, 3)
            ZStack(alignment: .leading) {
                TextField("", text: $draft.captureText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(.clear)
                    .modifier(NXAutofocus(refocus: refocus, caretAtEnd: voice?.filledField == true))
                    .accessibilityLabel("New task")
                    .accessibilityHint("Type the task. \(readsDates ? "A date, #label" : "A #label"), !priority or ~estimate in the text is read as you type, as in \(example).")
                    .accessibilityIdentifier("capture.title")
                    .accessibilityActions {
                        if let add {
                            Button("Add task") { add(false) }
                            Button("Add task and keep capture open") { add(true) }
                        }
                    }
                // The tinted copy of the field's text, which scrolls with it
                // once the text is wider than the card. Over the field, so a
                // selection's highlight shows under the text, not over it.
                // VoiceOver reads the field.
                styled(parse)
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: -scroll)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 24)
            .background { NXFieldScroll { scroll = $0 } }
            .clipped()
            if voice != nil {
                Button(action: toggleVoice) {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NX.ink(0.45))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Say tasks (⌥⌘V)")
                .accessibilityLabel("Say tasks")
                .accessibilityHint("Listens for one or more tasks, with their dates, lists and labels.")
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 6, trailing: 18))

        NXFlow(spacing: 6) {
            ForEach(chips(parse)) { NXChip(chip: $0, fresh: $0.pops != .never) }
        }
        .frame(minHeight: 22, alignment: .leading)
        .padding(EdgeInsets(top: 6, leading: 46, bottom: 12, trailing: 18))
    }

    // MARK: Voice

    private func toggleVoice() {
        voice?.toggle(for: draft, lists: library.lists, labels: library.labels, onSave: onVoiceSave)
    }

    private var voiceFailure: VoiceCaptureFailure? {
        if case let .failed(failure) = voice?.phase { failure } else { nil }
    }

    /// The tasks heard, each with what it saves and where it goes when that
    /// isn't the lit destination, and a way to leave one out.
    private var heard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !draft.captureText.isEmpty {
                Text("Your typed draft is kept. Add these tasks, then continue typing.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(draft.spokenTasks) { task in
                HStack(alignment: .top, spacing: 11) {
                    Circle()
                        .strokeBorder(NX.ink(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [2.6, 2.2]))
                        .frame(width: 17, height: 17)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.snapshot.title)
                            .font(.system(size: 15))
                            .foregroundStyle(NX.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        let chips = spokenChips(task)
                        if !chips.isEmpty {
                            NXFlow(spacing: 6) {
                                ForEach(chips) { NXChip(chip: $0, fresh: true) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        draft.spokenTasks.removeAll { $0.id == task.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NX.ink(0.4))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Leave out")
                    .accessibilityLabel("Leave out “\(task.snapshot.title)”")
                }
                .accessibilityElement(children: .combine)
            }
            if voice?.usedIntelligence == true {
                Label("Read by Apple Intelligence", systemImage: "apple.intelligence")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NX.textQuaternary)
                    .padding(.leading, 28)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
    }

    /// A heard task's chips, as a typed task's, and its list's when it named
    /// one other than the lit destination.
    private func spokenChips(_ task: SpokenTask) -> [NXChipModel] {
        var chips = task.chips().map(model)
        if let list = task.listID.flatMap({ library.list($0) }), list.id != draft.captureListID {
            chips.insert(NXChipModel(id: "list", label: list.displayTitle, glyph: list), at: 0)
        }
        return chips
    }

    /// "Add to" and the lists wrap like the design's flex row, with the key
    /// hints on the trailing edge of the last line.
    private var destinations: some View {
        NXFlow(spacing: 6, alignment: .center, pinsLastToTrailing: true) {
            destinationChips
            hints
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var destinationChips: some View {
        Text("Add to")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NX.textTertiary)
            .padding(.trailing, 2)
            .frame(height: 23)
        ForEach(library.lists) { list in
            destination(list, isOn: draft.captureListID == list.id)
        }
    }

    /// The key hints, or for a moment what ⇧↩ just added.
    @ViewBuilder private var hints: some View {
        if let notice, !notice.failed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 10.5, weight: .semibold))
                Text(notice.text)
                captureUndoButton
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NX.greenText)
            .lineLimit(1)
            .fixedSize()
        } else {
            HStack(spacing: 6) {
                Text(hint)
                captureUndoButton
            }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NX.textQuaternary)
                .fixedSize()
        }
    }

    @ViewBuilder private var captureUndoButton: some View {
        if let undoCapture {
            Button("Undo", action: undoCapture)
                .buttonStyle(.plain)
                .foregroundStyle(style.accent)
                .help("Undo added tasks (⌘Z)")
                .accessibilityLabel("Undo added tasks")
                .accessibilityIdentifier("capture.undo")
        }
    }

    private var hint: String {
        if voice?.isActive == true { return "↩ done · esc cancel" }
        let heard = draft.spokenTasks.count
        if heard > 0 { return "↩ add \(heard == 1 ? "task" : "\(heard) tasks") · esc leave out" }
        return voice == nil ? "⇥ destination · ↩ add · ⇧↩ add another" : "⇥ destination · ↩ add · ⌥⌘V speak"
    }

    /// Whether Settings reads dates from typed text, which the ghost and the
    /// field's hint promise only while it does.
    private var readsDates: Bool { draft.settings.parsesNaturalLanguageDates }

    /// The design's ghost, without its date while dates aren't read.
    private var example: String { readsDates ? "Pay deposit friday 6pm #travel ~15m" : "Pay deposit #travel ~15m" }

    /// The typed text with its tokens tinted, plus the placeholder ghost.
    private func styled(_ parse: CaptureParse) -> some View {
        guard !parse.text.isEmpty else {
            return Text(example).foregroundStyle(NX.textQuaternary).textRenderer(NXTokenRenderer())
        }
        let text = parse.segments.reduce(Text(verbatim: "")) { text, segment in
            guard let kind = segment.kind else { return Text("\(text)\(Text(verbatim: segment.text).foregroundStyle(NX.ink))") }
            let tone = Self.tone(kind, accent: style.accent, label: kind == .label ? labelColor(segment.text) : nil)
            let token = Text(verbatim: segment.text).foregroundStyle(tone)
                .customAttribute(NXCaptureToken(segment: segment.id, tone: tone))
            return Text("\(text)\(token)")
        }
        return text.textRenderer(NXTokenRenderer())
    }

    static func tone(_ kind: CaptureParse.Kind, accent: Color, label: Color? = nil) -> Color {
        switch kind {
        case .label: label ?? NX.textTertiary
        case .priority: NX.redText
        default: accent
        }
    }

    /// Every token previews as soon as it's typed, from the same parse and
    /// draft Return saves, so the chips show what it will store, in the order
    /// the tokens were typed (`CaptureParse.chips`). Only a typed token's chip
    /// pops in; the Today and the label screen's label, which nothing typed
    /// brought, never pop.
    private func chips(_ parse: CaptureParse) -> [NXChipModel] {
        var chips = parse.chips(for: draft.capturePreview(parse), forToday: draft.captureForToday).map(model)
        // A label screen adds its own label, unless the text names it already.
        if let label = draft.captureLabelID.flatMap({ env.store.label(id: $0) }),
           !parse.labels.contains(label.name.lowercased()) {
            chips.append(NXChipModel(id: "screen-label", label: label.name, tone: .label(label.nxColor), pops: .never))
        }
        return chips
    }

    private func model(_ chip: CaptureChip) -> NXChipModel {
        switch chip.kind {
        case .day: NXChipModel(id: chip.id, label: chip.label, icon: "calendar", tone: .accent, pops: chip.typed ? .withRow : .never)
        case .time: NXChipModel(id: chip.id, label: chip.label, icon: "bell", tone: .accent)
        case .repeatRule: NXChipModel(id: chip.id, label: chip.label, icon: "repeat", tone: .accent)
        case .label:
            NXChipModel(id: chip.id, label: chip.label, tone: labelColor(chip.label).map(NXTone.label) ?? .neutral)
        case let .priority(priority):
            NXChipModel(id: chip.id, label: chip.label, icon: "exclamationmark", tone: Self.priorityTone(priority),
                        fill: priority == .high)
        case .estimate: NXChipModel(id: chip.id, label: chip.label, icon: "timer", tone: .accent)
        }
    }

    /// A typed label's own colour, when a label by that name exists.
    private func labelColor(_ name: String) -> Color? {
        let name = name.drop { $0 == "#" }.lowercased()
        return library.labels.first { $0.name.lowercased() == name }?.nxColor
    }

    private static func priorityTone(_ priority: TaskPriority) -> NXTone {
        switch priority {
        case .high: .over
        case .medium: .amber
        case .low, .none: .neutral
        }
    }

    private func destination(_ list: TaskList, isOn: Bool) -> some View {
        Button {
            draft.captureListID = list.id
            refocus += 1
        } label: {
            HStack(spacing: 4) {
                NXListGlyph(list: list, size: 11)
                Text(list.displayTitle).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .foregroundStyle(isOn ? Color.white : NX.textSecondary)
            .background(isOn ? style.accent : NX.ink(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to \(list.displayTitle)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        // The design's `background 140ms ease`.
        .animation(NX.cssEase(140), value: isOn)
    }
}

/// Voice capture at work on the capture card: a mic that swells with the
/// voice, the words heard so far (those still being made out paler), and
/// what it's doing, with its stop button.
private struct NXVoicePanel: View {
    @Environment(\.nextStyle) private var style
    let voice: VoiceCapture
    let stop: () -> Void

    var body: some View {
        let listener = voice.listener
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(style.accent.opacity(0.16))
                    .frame(width: 17 + 12 * listener.level, height: 17 + 12 * listener.level)
                Image(systemName: "mic.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
            .frame(width: 17, height: 17)
            .padding(.top, 3)
            .animation(.linear(duration: 0.08), value: listener.level)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                words(listener)
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                status
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.textTertiary)
                if let note = voice.intelligence.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(NX.textQuaternary)
                }
            }

            Button(action: stop) {
                Image(systemName: voice.phase == .listening ? "stop.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(voice.phase == .listening ? style.accent : NX.ink(0.3))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(voice.phase == .understanding)
            .help(voice.phase == .listening ? "Done (↩)" : "Stop")
            .accessibilityLabel(voice.phase == .listening ? "Done speaking" : "Stop")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice capture")
    }

    private func words(_ listener: VoiceListener) -> Text {
        guard !listener.transcript.isEmpty else {
            return Text(voice.phase == .listening ? "Say a task, or several…" : "")
                .foregroundStyle(NX.textQuaternary)
        }
        let settled = Text(verbatim: listener.confirmed).foregroundStyle(voice.phase == .understanding ? NX.textTertiary : NX.ink)
        let guess = Text(verbatim: listener.tentative).foregroundStyle(NX.textQuaternary)
        return Text("\(settled)\(guess)")
    }

    @ViewBuilder private var status: some View {
        switch voice.phase {
        case .preparing(nil):
            Text("Getting ready…")
        case let .preparing(progress?):
            Text("Downloading speech recognition · \(Int(progress * 100))%")
        case .understanding:
            if voice.intelligence == .available {
                Label("Reading with Apple Intelligence…", systemImage: "apple.intelligence")
            } else {
                Text("Reading…")
            }
        default:
            Text("Listening · pause when you’re done")
        }
    }
}

/// Why voice capture didn't listen, with the way to let it where there is one.
private struct NXVoiceFailureLine: View {
    let failure: VoiceCaptureFailure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "mic.slash.fill").font(.system(size: 10.5, weight: .semibold))
            Text(failure.message).fixedSize(horizontal: false, vertical: true)
            if failure == .microphoneDenied,
               let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                Button("Open Settings") { NSWorkspace.shared.open(settings) }
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(failure == .nothingHeard ? NX.textTertiary : NX.redText)
    }
}

/// Marks a capture token's runs so `NXTokenRenderer` can draw its chip. The
/// segment tells one token from the next, since a token set in more than one
/// font (a fallback for another script, say) arrives as several runs.
private struct NXCaptureToken: TextAttribute {
    let segment: Int
    let tone: Color
}

/// Draws each token on a softly rounded tint with a 1.5pt rule along the
/// inside of its bottom edge, behind the unchanged glyphs, so the tinted
/// text still lines up with the field typed into underneath.
private struct NXTokenRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // One chip per token, across all of its runs.
            var chips: [(token: NXCaptureToken, bounds: CGRect)] = []
            for run in line {
                guard let token = run[NXCaptureToken.self] else { continue }
                let bounds = run.typographicBounds.rect
                if let last = chips.last, last.token.segment == token.segment {
                    chips[chips.count - 1].bounds = last.bounds.union(bounds)
                } else {
                    chips.append((token, bounds))
                }
            }
            for (token, bounds) in chips {
                let chip = Path(roundedRect: bounds, cornerRadius: 5, style: .continuous)
                context.fill(chip, with: .color(token.tone.opacity(0.1)))
                var rule = context
                rule.clip(to: chip)
                rule.fill(Path(CGRect(x: bounds.minX, y: bounds.maxY - 1.5, width: bounds.width, height: 1.5)),
                          with: .color(token.tone.opacity(0.33)))
            }
            for run in line { context.draw(run) }
        }
    }
}

// MARK: - Search

/// The app's search (tasks, notes, headings, list titles and summaries,
/// archived lists, diacritic-insensitive) in the Next overlay.
enum NXSearch {
    /// Results listed at once, as the design's; typing more narrows them.
    static let shownLimit = 12

    @MainActor
    static func options(_ workbench: Workbench) -> SearchOptions {
        var options = SearchOptions()
        options.query = workbench.searchQuery
        options.includesCompleted = workbench.searchIncludesCompleted
        return options
    }

    /// The listed results. The last answer stays listed while the query typed
    /// since is searched, so the list narrows rather than blanking; an empty
    /// field lists nothing, even before the session hears of it.
    @MainActor
    static func hits(_ session: SearchSession, workbench: Workbench) -> [SearchHit] {
        guard !options(workbench).needle.isEmpty else { return [] }
        return Array(session.hits.prefix(shownLimit))
    }

    /// Whether the results for the query typed now are still to come; the
    /// listed ones answer an older query.
    @MainActor
    static func isAnswering(_ session: SearchSession, workbench: Workbench) -> Bool {
        let options = options(workbench)
        return !options.needle.isEmpty && (session.isSearching || session.hitsOptions != options)
    }

    /// Whether Return waits for the answer to open its first result. Typing
    /// puts the choice back on the first row, so a choice further down was
    /// made among the listed rows, and it opens as they are.
    @MainActor
    static func waitsForAnswer(_ session: SearchSession, workbench: Workbench) -> Bool {
        workbench.searchIndex == 0 && isAnswering(session, workbench: workbench)
    }

    /// Tasks open in the inspector on their Next screen and lists on theirs.
    /// Notes, headings, summaries and archived content are revealed in the
    /// list's document, as the app's search always has, for the visit only:
    /// the list's saved presentation stays (`Navigator.reveal`). A listed
    /// result opens with the query it was found for, even while a newer one
    /// is searched.
    @MainActor
    static func open(_ hit: SearchHit, env: AppEnvironment, library: NextLibrary, overlays: NXOverlayState) {
        let workbench = env.workbench
        let request: ContentReveal
        do {
            let context = env.store.context
            request = try ContentReveal.resolve(hit.id, field: hit.field, query: overlays.search.hitsOptions.needle,
                                                blocks: context.fetch(FetchDescriptor<Block>()),
                                                lists: context.fetch(FetchDescriptor<TaskList>()))
        } catch {
            overlays.searchUnavailable = error.localizedDescription
            return
        }
        overlays.willNavigate()
        env.navigator.isSearchOpen = false
        let list = request.isArchived ? nil : library.list(request.listID)
        if let list, request.destination == .list(list.id), request.field == .text {
            workbench.go(workbench.route(for: list))
        } else if let list, let taskID = request.taskID, request.blockID == taskID {
            workbench.go(workbench.route(for: list))
            // Once the new screen is up, so it scrolls to the row.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { workbench.inspect(taskID) }
        } else {
            env.navigator.reveal(request)
        }
    }
}

/// Feeds the search session the library, rebuilt only when records change,
/// not on every keystroke.
private struct NXSearchCorpus: View {
    let session: SearchSession
    @Query private var blocks: [Block]
    @Query private var lists: [TaskList]

    var body: some View {
        let corpus = SearchCorpus(blocks: blocks, lists: lists)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: corpus, initial: true) { _, updated in session.update(corpus: updated) }
            .accessibilityHidden(true)
    }
}

private struct NXSearchCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let overlays: NXOverlayState
    /// The result the pointer just moved the highlight to.
    @State private var pointedID: SearchDestination?

    var body: some View {
        @Bindable var workbench = env.workbench
        let session = overlays.search
        let options = NXSearch.options(workbench)
        let hits = NXSearch.hits(session, workbench: workbench)
        let index = min(workbench.searchIndex, max(0, hits.count - 1))
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(NX.ink(0.4))
                TextField("Find a task, note, or list", text: $workbench.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5))
                    .foregroundStyle(NX.ink)
                    .modifier(NXAutofocus())
                    .onChange(of: workbench.searchQuery) { _, _ in workbench.searchIndex = 0 }
                Button("Include completed") { workbench.searchIncludesCompleted.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(workbench.searchIncludesCompleted ? Color.white : NX.textTertiary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(workbench.searchIncludesCompleted ? style.accent : NX.ink(0.06),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .fixedSize()
                    // The design's on/off pill.
                    .accessibilityAddTraits(.isToggle)
                    .accessibilityValue(workbench.searchIncludesCompleted ? "On" : "Off")
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }

            NXOverlayList {
                ForEach(Array(hits.enumerated()), id: \.element.id) { offset, hit in
                    NXSearchRow(hit: hit, needle: session.hitsOptions.needle, isOn: offset == index)
                        .id(hit.id)
                        .onHover { inside in
                            guard inside, offset != index else { return }
                            pointedID = hit.id
                            workbench.searchIndex = offset
                        }
                        // The row clicked opens, even while a newer query is searched.
                        .onTapGesture { NXSearch.open(hit, env: env, library: library, overlays: overlays) }
                        .accessibilityAction { NXSearch.open(hit, env: env, library: library, overlays: overlays) }
                }
                Text(footer(hits, session: session, typed: options))
                    .font(.system(size: 12.5))
                    .foregroundStyle(NX.textQuaternary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            }
            .modifier(NXScrollToIndex(ids: hits.map(\.id), index: index))
        }
        .frame(maxWidth: 640)
        .modifier(NXAnnounceHighlight(id: hits.indices.contains(index) ? hits[index].id : nil,
                                      spoken: hits.indices.contains(index) ? NXSearchRow.spoken(hits[index]) : nil,
                                      pointed: $pointedID))
        .background { NXSearchCorpus(session: session) }
        .onChange(of: options, initial: true) { _, updated in
            overlays.searchUnavailable = nil
            session.update(options: updated)
        }
        // Return pressed before the answer opens its first result once it
        // arrives, unless the query changed in between.
        .onChange(of: NXSearch.isAnswering(session, workbench: workbench)) { _, answering in
            guard !answering, let pending = overlays.pendingSearchOpen else { return }
            overlays.pendingSearchOpen = nil
            guard pending == NXSearch.options(workbench),
                  let first = NXSearch.hits(session, workbench: workbench).first else { return }
            NXSearch.open(first, env: env, library: library, overlays: overlays)
        }
        .onDisappear {
            session.cancel()
            overlays.pendingSearchOpen = nil
        }
    }

    /// Describes the listed results; "Searching…" only once a search is slow.
    private func footer(_ hits: [SearchHit], session: SearchSession, typed: SearchOptions) -> String {
        if let unavailable = overlays.searchUnavailable { return unavailable }
        let options = session.hitsOptions
        if typed.needle.isEmpty || (options.needle.isEmpty && !session.isSlow) { return "Search tasks, notes and lists" }
        if session.isSlow { return "Searching…" }
        // The rows listed, as the design counts them.
        if !hits.isEmpty { return "\(hits.count) \(hits.count == 1 ? "result" : "results") · ↑↓ choose · ↩ open" }
        return "Nothing matches “\(options.needle)”" + (options.includesCompleted ? "" : " — try including completed")
    }
}

private struct NXSearchRow: View {
    @Environment(\.nextStyle) private var style
    let hit: SearchHit
    let needle: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: hit.symbol)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? NX.ink(0.6) : NX.ink(0.4))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(hit.title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !hit.snippet.isEmpty {
                    Text(highlighted(hit.snippet))
                        .font(.system(size: 12))
                        .foregroundStyle(NX.textSecondary)
                        .lineLimit(2)
                }
                context
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(isOn ? NX.ink(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        // One result, which Return opens while it's highlighted.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(hit))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// The title, the matched passage and where it is, as VoiceOver reads them.
    static func spoken(_ hit: SearchHit) -> String {
        let context = hit.context + (hit.dueDate.map { ", " + NXFormat.dueLabel($0) } ?? "")
            + (hit.field == .note ? ", matched in note" : "")
        return [hit.title, hit.snippet, context].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Where the hit is, after its list's icon, as the design's `emoji + " " + name`,
    /// then its due day, and "matched in note" when only its note matched.
    private var context: Text {
        let text = hit.context + (hit.dueDate.map { " · " + NXFormat.dueLabel($0) } ?? "")
            + (hit.field == .note ? " · matched in note" : "")
        guard let icon = hit.listIcon else { return Text(verbatim: text) }
        return Text("\(NXListGlyph.text(icon, size: 11)) \(text)")
    }

    /// Tints the match with the same folding the search used.
    private func highlighted(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        if !needle.isEmpty,
           let range = value.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
            value[range].backgroundColor = style.accent.opacity(0.15)
            value[range].foregroundColor = style.accent
        }
        return value
    }
}

/// Up to 380pt of rows, scrolling only when they overflow.
private struct NXOverlayList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                content()
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Palette

struct NXCommand: Identifiable {
    var id: String
    var icon: String
    var label: String
    var key = ""
    var tone: Color?
    var needsTarget = false
    /// Leaves the current screen or task, so focus isn't handed back to it.
    var navigates = false
    var run: @MainActor () -> Void
}

enum NXPalette {
    /// The commands the query matches, those that act on tasks only while
    /// one is focused or selected, unless `anyTarget` asks what would match
    /// with one.
    @MainActor
    static func commands(env: AppEnvironment, library: NextLibrary, anyTarget: Bool = false) -> [NXCommand] {
        let workbench = env.workbench
        let hasTarget = anyTarget || !workbench.targetTasks.isEmpty
        let query = workbench.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        func act(_ body: @escaping @MainActor ([UUID]) -> Void) -> @MainActor () -> Void {
            {
                let ids = workbench.targetTasks.map(\.id)
                if !ids.isEmpty { body(ids) }
            }
        }
        let nav: [(AppRoute, String, String, String)] = [
            (.inbox, "tray", "Go to Inbox", "G I"),
            (.today, "sun.max", "Go to Today", "G T"),
            (.calendar, "calendar", "Go to Calendar", "G C"),
            (.tasks, "checklist", "Go to Tasks", "G A"),
            (.lists, "square.2.layers.3d", "Go to Lists", "G L"),
            (.activity, "square.grid.2x2", "Go to Activity", "G H"),
            (.trash, "trash", "Go to Trash", ""),
            (.settings, "gearshape", "Open Settings", "⌘,"),
        ]
        var all: [NXCommand] = [
            NXCommand(id: "done", icon: "checkmark.circle", label: "Mark as done", key: "E", needsTarget: true,
                      run: act { workbench.complete($0) }),
            NXCommand(id: "today", icon: "calendar", label: "Due today", key: "T", needsTarget: true,
                      run: act { workbench.schedule($0, offset: 0) }),
            NXCommand(id: "tomorrow", icon: "sun.horizon", label: "Due tomorrow", key: "M", needsTarget: true,
                      run: act { workbench.schedule($0, offset: 1) }),
            NXCommand(id: "plan", icon: "calendar.badge.clock", label: "Plan for today", key: "P", needsTarget: true,
                      run: act { workbench.plan($0) }),
            NXCommand(id: "fit", icon: "sparkles", label: "Find a slot in the calendar", needsTarget: true,
                      run: act { $0.forEach { workbench.fit($0) } }),
            NXCommand(id: "work", icon: "play.fill", label: "Start working", needsTarget: true,
                      run: act { workbench.startWork($0[0]) }),
            NXCommand(id: "star", icon: "star", label: "Star", key: "F", needsTarget: true,
                      run: act { workbench.star($0) }),
        ]
        all += library.lists.map { list in
            NXCommand(id: "move-\(list.id)", icon: "arrow.turn.down.right", label: "Move to \(list.displayTitle)", needsTarget: true,
                      run: act { workbench.move($0, to: list.id) })
        }
        all += [
            NXCommand(id: "details", icon: "sidebar.right", label: "Open details", key: "↩", needsTarget: true, navigates: true,
                      run: act { workbench.inspect($0[0]) }),
            NXCommand(id: "page", icon: workbench.isTaskPageOpen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                      label: workbench.isTaskPageOpen ? "Collapse details" : "Expand details", key: "⇧⌘↩",
                      needsTarget: true, navigates: true,
                      run: act { ids in
                          if !workbench.isTaskPageOpen, env.navigator.openTaskID != ids[0] { workbench.inspect(ids[0]) }
                          workbench.toggleTaskPage()
                      }),
            NXCommand(id: "trash", icon: "trash", label: "Move to Trash", key: "D", tone: NX.redText, needsTarget: true,
                      navigates: true, run: act { workbench.trash($0) }),
            NXCommand(id: "new", icon: "plus.circle", label: "New task", key: "N") { workbench.openCapture() },
            NXCommand(id: "search", icon: "magnifyingglass", label: "Search", key: "/") { env.navigator.isSearchOpen = true },
            NXCommand(id: "undo", icon: "arrow.uturn.backward", label: "Undo last change", key: "⌘Z") { workbench.undoLast() },
            // The sheet leaves the page as it was, so focus goes back where it
            // was, as Help ▸ Keyboard Shortcuts leaves it.
            NXCommand(id: "shortcuts", icon: "keyboard", label: "Keyboard shortcuts", key: "⌘/") {
                env.navigator.isShortcutSheetOpen = true
            },
        ]
        all += nav.map { route, icon, label, key in
            NXCommand(id: "go-\(label)", icon: icon, label: label, key: key, navigates: true) { workbench.go(route) }
        }
        all += library.destinations.map { list in
            NXCommand(id: "open-\(list.id)", icon: "square.2.layers.3d", label: "Open \(list.displayTitle)", navigates: true) {
                workbench.go(.list(list.id))
            }
        }
        let filtered = all.enumerated().filter { _, command in
            (!command.needsTarget || hasTarget) && (query.isEmpty || command.label.lowercased().contains(query))
        }
        guard !query.isEmpty else { return filtered.map(\.element) }
        return filtered.sorted { a, b in
            let x = a.element.label.lowercased().range(of: query).map { a.element.label.lowercased().distance(from: a.element.label.lowercased().startIndex, to: $0.lowerBound) } ?? 0
            let y = b.element.label.lowercased().range(of: query).map { b.element.label.lowercased().distance(from: b.element.label.lowercased().startIndex, to: $0.lowerBound) } ?? 0
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    /// Closes the palette, then runs the command once the card is gone.
    @MainActor
    static func run(_ command: NXCommand, env: AppEnvironment, overlays: NXOverlayState) {
        if command.navigates { overlays.willNavigate() }
        env.navigator.isCommandPaletteOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { command.run() }
    }
}

private struct NXPaletteCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let overlays: NXOverlayState
    /// The command the pointer just moved the highlight to.
    @State private var pointedID: String?

    var body: some View {
        @Bindable var workbench = env.workbench
        let commands = NXPalette.commands(env: env, library: library)
        let index = min(workbench.paletteIndex, max(0, commands.count - 1))
        let targets = workbench.targetTasks
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt").font(.system(size: 16)).foregroundStyle(NX.ink(0.4))
                TextField("Type an action or a place…", text: $workbench.paletteQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5))
                    .foregroundStyle(NX.ink)
                    .modifier(NXAutofocus())
                    .onChange(of: workbench.paletteQuery) { _, _ in workbench.paletteIndex = 0 }
                Text(targets.isEmpty ? "No task focused"
                     : targets.count == 1 ? NXFormat.short(targets[0].displayTitle) : "\(targets.count) selected")
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(NX.textTertiary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: 200, alignment: .trailing)
                    .fixedSize()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }

            NXOverlayList {
                ForEach(Array(commands.enumerated()), id: \.element.id) { offset, command in
                    NXPaletteRow(command: command, isOn: offset == index)
                        .onHover { inside in
                            guard inside, offset != index else { return }
                            pointedID = command.id
                            workbench.paletteIndex = offset
                        }
                        .onTapGesture { NXPalette.run(command, env: env, overlays: overlays) }
                        .accessibilityAction { NXPalette.run(command, env: env, overlays: overlays) }
                }
                if commands.isEmpty {
                    // Task actions only list with a task to act on: when one
                    // of them is what the query names, say so rather than
                    // show an empty card.
                    let needsTask = targets.isEmpty && !NXPalette.commands(env: env, library: library, anyTarget: true).isEmpty
                    Text(needsTask ? "“\(NXFormat.short(workbench.paletteQuery))” acts on a task. Focus or select one first."
                                   : "No actions match “\(NXFormat.short(workbench.paletteQuery))”.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(NX.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .modifier(NXScrollToIndex(ids: commands.map(\.id), index: index))
        }
        .frame(maxWidth: 560)
        .modifier(NXAnnounceHighlight(id: commands.indices.contains(index) ? commands[index].id : nil,
                                      spoken: commands.indices.contains(index) ? commands[index].label : nil,
                                      pointed: $pointedID))
    }
}

/// Tells VoiceOver which row Return now runs, from the field: after ↑ or ↓,
/// or when typing brings a new row to the top. A row the pointer highlighted
/// isn't read out, as the pointer following VoiceOver's cursor would have it
/// spoken twice.
private struct NXAnnounceHighlight<ID: Hashable>: ViewModifier {
    let id: ID?
    let spoken: String?
    @Binding var pointed: ID?

    func body(content: Content) -> some View {
        content.onChange(of: id) { _, id in
            let byPointer = id != nil && id == pointed
            pointed = nil
            guard !byPointer, id != nil, let spoken else { return }
            AccessibilityNotification.Announcement(spoken).post()
        }
    }
}

/// Keeps the chosen row visible as arrows move through the palette or results.
private struct NXScrollToIndex<ID: Hashable>: ViewModifier {
    let ids: [ID]
    let index: Int

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: index) { _, index in
                guard ids.indices.contains(index) else { return }
                proxy.scrollTo(ids[index])
            }
        }
    }
}

private struct NXPaletteRow: View {
    let command: NXCommand
    let isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 14))
                .foregroundStyle(command.tone ?? NX.ink(0.5))
                .frame(width: 16)
            Text(command.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            Text(command.key).font(NX.mono(10.5)).foregroundStyle(NX.textQuaternary)
        }
        .foregroundStyle(NX.ink)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(isOn ? NX.ink(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        // One command, which Return runs while it's highlighted.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(command.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .id(command.id)
    }
}
