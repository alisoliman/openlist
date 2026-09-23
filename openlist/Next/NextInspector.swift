//
//  NextInspector.swift
//  openlist
//

import SwiftUI

/// The 360pt panel that slides in from the right with one task's details.
struct NextInspector: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    @State private var title = ""
    @State private var note = ""
    @State private var pickingDate = false
    @State private var pickedDate = Date.now
    @FocusState private var focus: Field?

    enum Field { case title, note }

    private var workbench: Workbench { env.workbench }

    var body: some View {
        let list = library.list(task.listID)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let list { NXListGlyph(list: list, size: 12) }
                Text(list?.displayTitle ?? "No list")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.55))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button { env.navigator.closeTask() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                                padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                                foreground: NX.ink(0.45), hoverForeground: NX.ink))
                .help("Close (Esc)")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleRow
                    properties(list: list)
                    planCard
                    noteBox
                    activity
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)

            HStack(spacing: 6) {
                Button { workbench.trash([task.id]) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash").font(.system(size: 12.5))
                        Text("Trash").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.red.opacity(0.1), radius: 8,
                                                padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9),
                                                foreground: NX.ink(0.6), hoverForeground: NX.redText))
                Spacer(minLength: 8)
                startButton
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(NX.inspector)
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.1)).frame(width: 0.5) }
        .shadow(color: NX.shadowWarm.opacity(0.1), radius: 17, x: -14)
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear(perform: load)
        .onChange(of: task.id) { _, _ in load() }
        .onChange(of: task.text) { _, _ in if focus != .title { title = task.displayTitle } }
        .onChange(of: focus) { old, _ in
            if old == .title { commitTitle() }
            if old == .note { commitNote() }
        }
        .onDisappear {
            commitTitle()
            commitNote()
        }
    }

    private func load() {
        title = task.displayTitle
        note = task.note
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.displayTitle else { title = task.displayTitle; return }
        env.store.setText(trimmed, for: task)
    }

    private func commitNote() {
        guard note != task.note else { return }
        env.store.setNote(note, for: task)
    }

    // MARK: Title

    private var titleRow: some View {
        let closing = workbench.closing[task.id]
        return HStack(alignment: .top, spacing: 10) {
            NXCheckbox(filled: task.isCompleted || closing != nil, closing: closing, priority: task.priority, size: 18) {
                workbench.toggle(task.id)
            }
            .padding(.top, 3)
            TextField("Task", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(task.isCompleted ? NX.ink(0.45) : NX.ink)
                .strikethrough(task.isCompleted, color: NX.ink(0.45))
                .focused($focus, equals: .title)
                .onSubmit { focus = nil }
        }
    }

    // MARK: Properties

    private func properties(list: TaskList?) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 11) {
            GridRow {
                propertyLabel("List")
                VStack(alignment: .leading, spacing: 4) {
                    Text(list?.displayTitle ?? "No list")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                    NXFlow(spacing: 4) {
                        ForEach(library.lists, id: \.id) { option in
                            NXInspectorPill(isOn: option.id == task.listID, padding: EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7)) {
                                if option.id != task.listID { workbench.move([task.id], to: option.id, quiet: true) }
                            } label: {
                                NXListGlyph(list: option, size: 13)
                            }
                            .help(option.displayTitle)
                        }
                    }
                }
            }
            GridRow {
                propertyLabel("Due")
                NXFlow(spacing: 4) {
                    ForEach(dueOptions, id: \.label) { option in
                        NXInspectorPill(isOn: isDue(option.offset)) {
                            workbench.schedule([task.id], offset: option.offset)
                        } label: {
                            Text(option.label)
                        }
                    }
                    NXInspectorPill(isOn: false) {
                        pickedDate = task.dueDate ?? .now
                        pickingDate = true
                    } label: {
                        Image(systemName: "calendar").font(.system(size: 11))
                    }
                    .help("Pick a date (⌃D)")
                    .popover(isPresented: $pickingDate, arrowEdge: .bottom) { datePicker }
                }
            }
            GridRow {
                propertyLabel("Priority")
                HStack(spacing: 4) {
                    ForEach([TaskPriority.none, .low, .medium, .high], id: \.self) { priority in
                        let on = task.priority == priority
                        NXInspectorPill(isOn: on) { workbench.setPriority(task.id, priority) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(on ? .white : Self.priorityColor(priority)).frame(width: 6, height: 6)
                                Text(Self.priorityTitle(priority))
                            }
                        }
                    }
                }
            }
            if !library.labels.isEmpty {
                GridRow {
                    propertyLabel("Labels")
                    NXFlow(spacing: 4) {
                        ForEach(library.labels, id: \.id) { label in
                            let on = task.labelIDs.contains(label.id)
                            let color = label.nxColor
                            Button { workbench.toggleLabel(task.id, labelID: label.id) } label: {
                                Text("#\(label.name)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(on ? .white : color)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .background(on ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeOut(duration: 0.14), value: on)
                        }
                    }
                }
            }
            GridRow {
                propertyLabel("Starred")
                Button { workbench.star([task.id]) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: task.isStarred ? "star.fill" : "star").font(.system(size: 11.5, weight: .semibold))
                        Text(task.isStarred ? "Starred" : "Not starred")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(task.isStarred ? NX.amberText : NX.ink(0.66))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(task.isStarred ? NX.amber.opacity(0.16) : NX.ink(0.05),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Star (F)")
            }
        }
    }

    private var datePicker: some View {
        VStack(alignment: .trailing, spacing: 10) {
            DatePicker("Due", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Button("Clear") {
                    workbench.schedule([task.id], offset: nil)
                    pickingDate = false
                }
                Spacer()
                Button("Set date") {
                    workbench.schedule([task.id], offset: NXFormat.dayOffset(pickedDate))
                    pickingDate = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func propertyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(NX.ink(0.45))
            .frame(width: 78, alignment: .leading)
            .gridColumnAlignment(.leading)
    }

    private var nextWeekOffset: Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: .now)
        let days = (calendar.firstWeekday - weekday + 7) % 7
        return days == 0 ? 7 : days
    }

    private var dueOptions: [(label: String, offset: Int?)] {
        var options: [(String, Int?)] = [("Today", 0), ("Tomorrow", 1), ("Next week", nextWeekOffset), ("None", nil)]
        if let due = task.dueDate {
            let offset = NXFormat.dayOffset(due)
            if ![0, 1, nextWeekOffset].contains(offset) { options.insert((NXFormat.dueLabel(due), offset), at: 0) }
        }
        return options
    }

    private func isDue(_ offset: Int?) -> Bool {
        guard let due = task.dueDate else { return offset == nil }
        return offset == NXFormat.dayOffset(due)
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none: NX.ink(0.25)
        case .low: NX.inbox
        case .medium: NX.amber
        case .high: NX.red
        }
    }

    static func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "None"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }

    // MARK: Plan card

    private var planCard: some View {
        let planned = workbench.isPlanned(task)
        let estimate = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : env.workbench.defaultEstimate
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 13)).foregroundStyle(style.accent)
                Text("Plan for today").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NX.ink)
                Spacer(minLength: 6)
                NXToggle(isOn: planned) { workbench.plan([task.id]) }
                    .help("Plan for today (P)")
            }
            HStack(spacing: 8) {
                Text("Estimate").font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.5))
                Spacer(minLength: 6)
                stepper("minus") { workbench.setEstimate(task.id, delta: -5) }
                Text("\(estimate) min")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink)
                    .contentTransition(.numericText())
                    .frame(width: 52)
                stepper("plus") { workbench.setEstimate(task.id, delta: 5) }
            }
            .padding(.top, 11)
            Text(slotText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
        }
        .padding(12)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
    }

    private var slotText: String {
        guard let placement = env.store.placements(taskID: task.id).min(by: { $0.start < $1.start }) else {
            return "Not in the calendar yet — ⌘K › Find a slot"
        }
        let offset = NXFormat.dayOffset(placement.start)
        let day = offset == 0 ? "today" : placement.start.formatted(.dateTime.weekday(.abbreviated).day())
        return "In the calendar \(day), \(NXFormat.clock(placement.start))–\(NXFormat.clock(placement.end))"
    }

    private func stepper(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 15, height: 15)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), radius: 6,
                                        padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                        foreground: NX.ink(0.6)))
        .background(NX.ink(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: Note & activity

    private var noteBox: some View {
        TextField("Add a note", text: $note, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(NX.ink(0.7))
            .focused($focus, equals: .note)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(NX.ink(focus == .note ? 0.05 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var activity: some View {
        let captured = library.isInbox(task) ? "Inbox" : library.list(task.listID)?.displayTitle ?? "a list"
        let entries = workbench.entries(for: task.id).reversed()
        return VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.74)
                .textCase(.uppercase)
                .foregroundStyle(NX.ink(0.36))
                .padding(.bottom, 8)
            ForEach(Array(entries)) { entry in
                activityRow(icon: entry.icon, text: entry.label, date: entry.at)
                    .transition(.offset(y: 6).combined(with: .opacity))
            }
            activityRow(icon: "plus.circle", text: "Captured in \(captured)", date: task.createdAt)
        }
        .animation(style.ease(220), value: workbench.entries(for: task.id).count)
    }

    private func activityRow(icon: String, text: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.4)).frame(width: 14)
            Text(text).font(.system(size: 12)).foregroundStyle(NX.ink(0.66)).frame(maxWidth: .infinity, alignment: .leading)
            Text(NXFormat.relative(date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.36))
        }
        .padding(.vertical, 5)
    }

    private var startButton: some View {
        let working = workbench.workTask?.id == task.id
        return Button { if !working { workbench.startWork(task.id) } } label: {
            HStack(spacing: 5) {
                Image(systemName: working ? "timer" : "play.fill").font(.system(size: 12))
                Text(working ? "Working…" : "Start working").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(working ? NX.ink(0.55) : .white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(working ? NX.ink(0.06) : style.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(task.isCompleted)
    }
}

/// The inspector's small toggle pills: accent when on, faint grey when off.
struct NXInspectorPill<Label: View>: View {
    @Environment(\.nextStyle) private var style
    let isOn: Bool
    var padding = EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isOn ? .white : NX.ink(0.66))
                .padding(padding)
                .background(isOn ? style.accent : hovering ? NX.ink(0.09) : NX.ink(0.05),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isOn)
    }
}
