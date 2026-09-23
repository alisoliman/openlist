//
//  NextInbox.swift
//  openlist
//

import SwiftUI

struct NextInboxScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library

    var body: some View {
        let workbench = env.workbench
        let queue = library.inboxQueue(workbench)
        let kept = library.keptInbox(workbench)
        var groups: [NXGroup] = []
        if queue.count > 1 {
            groups.append(NXGroup(id: "next", title: "Up next", icon: "text.line.last.and.arrowtriangle.forward", color: NX.inbox,
                                  rows: Array(queue.dropFirst())))
        }
        if !kept.isEmpty {
            groups.append(NXGroup(id: "kept", title: "Kept for later", icon: "clock", color: NX.ink(0.45), rows: kept,
                                  collapsible: true))
        }
        let subtitle = "\(queue.count) to triage" + (workbench.kept.isEmpty ? "" : " · \(kept.count) kept for later")
        return NXPage(rowIDs: (queue.first.map { [$0.id] } ?? []) + NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXScreenHeader(tile: .icon("tray.fill"), color: NX.inbox, title: "Inbox", subtitle: subtitle)
            Group {
                if let task = queue.first {
                    NXTriageCard(task: task, remaining: queue.count)
                        .id(task.id)
                } else {
                    NXTriageEmpty()
                }
            }
            .padding(.top, 22)
            NXGroupsStack(groups: groups, options: NXRowOptions(showList: false), topPadding: 10)
        }
    }
}

private struct NXTriageCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    let remaining: Int

    var body: some View {
        let workbench = env.workbench
        let exit = workbench.triageExit
        VStack(alignment: .leading, spacing: 0) {
            topLine
            Text(task.displayTitle)
                .font(.system(size: 22, weight: .medium))
                .kerning(-0.11)
                .foregroundStyle(NX.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            HStack(spacing: 6) {
                ForEach(chips) { NXChip(chip: $0) }
            }
            .frame(minHeight: 4)
            .padding(.top, 4)
            .padding(.horizontal, 18)

            HStack(alignment: .top, spacing: 18) {
                fileInto.frame(maxWidth: .infinity, alignment: .topLeading)
                schedule.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            footer
        }
        .background(NX.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(exit == .done ? NX.green : NX.ink(0.12), lineWidth: exit == .done ? 2 : 0.5))
        .shadow(color: NX.shadowWarm.opacity(0.09), radius: 20, y: 14)
        .offset(x: exit == .left ? -90 : exit == .right ? 90 : 0,
                y: exit == .up ? -26 : exit == .down ? 26 : 0)
        .rotationEffect(.degrees(exit == .left ? -1.5 : exit == .right ? 1.5 : 0))
        .scaleEffect(exit == .up ? 0.97 : exit == .done ? 0.95 : 1)
        .opacity(exit == nil ? 1 : 0)
        .modifier(NXLiftIn())
    }

    private var chips: [NXChipModel] {
        var chips: [NXChipModel] = []
        if let due = task.dueDate {
            chips.append(NXChipModel(id: "due", label: NXFormat.dueLabel(due), icon: "calendar",
                                     tone: NXFormat.dayOffset(due) <= 0 ? .accent : .neutral))
        }
        if task.priority != .none {
            chips.append(NXChipModel(id: "prio", label: task.priority == .high ? "High priority" : task.priority.title,
                                     icon: "flag.fill", tone: .over))
        }
        return chips
    }

    private var topLine: some View {
        let workbench = env.workbench
        let total = min(12, workbench.reviewed + remaining)
        return HStack(spacing: 10) {
            Text("Triage")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.84)
                .textCase(.uppercase)
                .foregroundStyle(NX.inbox)
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= workbench.reviewed ? NX.inbox : NX.ink(0.12))
                        .frame(width: index == workbench.reviewed ? 16 : 5, height: 5)
                }
            }
            .animation(.easeOut(duration: 0.3), value: workbench.reviewed)
            Text("\(remaining) to go")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.42))
            Spacer(minLength: 8)
            Text("Captured \(NXFormat.relative(task.createdAt))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.4))
        }
        .padding(.top, 14)
        .padding(.horizontal, 18)
    }

    private var fileInto: some View {
        VStack(alignment: .leading, spacing: 0) {
            caps("File into")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(library.destinations.prefix(9).enumerated()), id: \.element.id) { index, list in
                    NXTriageListRow(key: index + 1, list: list, count: library.openCount(in: list.id)) {
                        env.workbench.triage(task, action: .left, listID: list.id)
                    }
                }
            }
        }
    }

    private var schedule: some View {
        let load = Dictionary(grouping: library.open.compactMap { $0.dueDate.map { NXFormat.dayOffset($0) } }, by: { $0 })
            .mapValues(\.count)
        return VStack(alignment: .leading, spacing: 0) {
            caps("Or schedule — stays in Inbox")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<8, id: \.self) { offset in
                    NXTriageDay(offset: offset, load: load[offset] ?? 0) {
                        env.workbench.triage(task, action: .up, offset: offset)
                    }
                }
            }
            Text("T today · M tomorrow · dots show what’s already due")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NX.ink(0.4))
                .padding(.top, 8)
        }
    }

    private var footer: some View {
        let workbench = env.workbench
        return HStack(spacing: 6) {
            footerButton("Already done", icon: "checkmark.circle", key: "E", hover: NX.green.opacity(0.12), hoverText: NX.greenText) {
                workbench.triage(task, action: .done)
            }
            footerButton("Discard", icon: "trash", key: "D", hover: NX.red.opacity(0.1), hoverText: NX.redText) {
                workbench.triage(task, action: .down)
            }
            footerButton("Details", icon: "sidebar.right", key: "↩", hover: NX.ink(0.06), hoverText: NX.ink) {
                workbench.inspect(task.id)
            }
            Spacer(minLength: 8)
            Button { workbench.triage(task, action: .right) } label: {
                HStack(spacing: 6) {
                    Text("Keep for later").font(.system(size: 12, weight: .semibold))
                    Text("→").font(NX.mono(10, weight: .medium)).opacity(0.6)
                }
            }
            .buttonStyle(NXHoverButtonStyle(hover: Color(hex: 0x2C2A31), radius: 8,
                                            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                            foreground: .white, hoverForeground: .white))
            .background(NX.inverse, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(NX.ink(0.02))
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
    }

    private func caps(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.74)
            .textCase(.uppercase)
            .foregroundStyle(NX.ink(0.36))
            .lineLimit(1)
            .padding(.bottom, 8)
    }

    private func footerButton(_ title: String, icon: String, key: String, hover: Color, hoverText: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 12, weight: .medium))
                Text(key).font(NX.mono(9.5, weight: .medium)).opacity(0.5)
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: hover, radius: 8,
                                        padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                                        foreground: NX.ink(0.7), hoverForeground: hoverText))
    }
}

private struct NXTriageListRow: View {
    let key: Int
    let list: TaskList
    let count: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text("\(key)")
                .font(NX.mono(10, weight: .semibold))
                .foregroundStyle(NX.ink(0.5))
                .frame(width: 16, height: 16)
                .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            NXListGlyph(list: list, size: 13)
            Text(list.displayTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(NX.ink(0.34))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(hovering ? NX.inbox.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help("File into \(list.displayTitle) (\(key))")
    }
}

private struct NXTriageDay: View {
    @Environment(\.nextStyle) private var style
    let offset: Int
    let load: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let date = NXFormat.day(offset: offset)
        VStack(spacing: 4) {
            Text(offset == 0 ? "Today" : offset == 1 ? "Tmrw" : date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.38)
                .textCase(.uppercase)
                .foregroundStyle(NX.ink(0.42))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(NX.ink)
            HStack(spacing: 2) {
                ForEach(0..<min(load, 4), id: \.self) { _ in
                    Circle().fill(load >= 3 ? NX.red : NX.ink(0.3)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(hovering ? style.accent.opacity(0.12) : NX.ink(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help(load == 0 ? "Nothing due" : "\(load) already due")
    }
}

private struct NXTriageEmpty: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let workbench = env.workbench
        HStack(spacing: 18) {
            Circle().fill(NX.green)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text("Inbox triaged").font(NX.serif(26)).foregroundStyle(NX.ink)
                Text("\(workbench.reviewed) reviewed this session. Tasks you kept or scheduled stay in Inbox until you file them.")
                    .font(.system(size: 13))
                    .foregroundStyle(NX.ink(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !workbench.kept.isEmpty {
                Button("Review kept tasks") {
                    workbench.kept = []
                    workbench.reviewed = 0
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), radius: 8,
                                                padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                                foreground: NX.ink(0.7)))
                .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 28)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .nxCardShadow(radius: 16, hairline: 0.1, drop: 0.06, y: 10, blur: 30)
        .modifier(NXLiftIn())
    }
}
