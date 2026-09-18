import SwiftUI

struct CalendarSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Calendar settings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
            Divider()
            CalendarSettingsView()
        }.frame(width: 620, height: 650)
    }
}

struct CalendarSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var preferences = CalendarPreferences()
    @State private var category: AvailabilityCategory = .work
    @State private var overrideDate = Date.now
    @State private var overrideWindows = [AvailabilityWindow(startMinute: 9 * 60, endMinute: 17 * 60)]
    @State private var overrideBreaks: [AvailabilityWindow] = []
    @State private var showsOverride = false
    @State private var editingOverrideID: UUID?
    @State private var isConnecting = false
    @State private var hasLoaded = false
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section("Work reminders") {
                @Bindable var calendar = env.calendar
                Toggle("Notify me about planned work when Openlist is in the background", isOn: $calendar.workNotificationsEnabled)
                Text("Suggestions stay quiet in the app. Time never starts automatically; extensions ask before moving other planned work.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Section("Planning") {
                HStack {
                    Text("Default estimate")
                    Spacer()
                    TextField("Minutes", value: $preferences.defaultEstimateMinutes, format: .number)
                        .labelsHidden()
                        .frame(width: 65).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Default estimate in minutes")
                    Text("minutes").foregroundStyle(Theme.secondaryText)
                }
                Stepper("Minimum session: \(preferences.minimumSessionMinutes) minutes", value: $preferences.minimumSessionMinutes, in: 5...120, step: 5)
                Text("A rolling four-week plan. Review affected tasks before extending work into their time.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .help("Tasks shorter than the minimum session can still use shorter slots.")
            }
            Section("Availability") {
                Picker("Hours", selection: $category) {
                    ForEach(AvailabilityCategory.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("Lists use either Work or Personal hours.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .help("Choose the availability category in each list's options.")
                ForEach(weekdays, id: \.self) { weekday in
                    DisclosureGroup {
                        AvailabilityWindowsEditor(title: "Available", windows: weeklyBinding(weekday, breaks: false))
                        AvailabilityWindowsEditor(title: "Breaks", windows: weeklyBinding(weekday, breaks: true))
                    } label: {
                        HStack {
                            Text(Calendar.current.weekdaySymbols[weekday - 1])
                            Spacer()
                            Text(windowSummary(profile.weekly[weekday] ?? []))
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            Section("Date-specific overrides") {
                Text("Replace a day's usual hours, or leave it unavailable.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                ForEach(profile.overrides.sorted { $0.date < $1.date }) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                            Text(windowSummary(item.windows)).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button("Edit") {
                            editingOverrideID = item.id; overrideDate = item.date; overrideWindows = item.windows; overrideBreaks = item.breaks; showsOverride = true
                        }
                        Button { changeProfile { $0.overrides.removeAll { $0.id == item.id } } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Remove override for \(item.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                Button("Add date override…") {
                    editingOverrideID = nil; overrideDate = .now; overrideWindows = []; overrideBreaks = []; showsOverride = true
                }
            }
            Section("Connected calendars") {
                Text(env.calendar.externalCalendars.authorizationDescription)
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                Text("Read-only busy time. Your calendar events are never changed.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                if env.calendar.externalCalendars.isConnected {
                    ForEach(env.calendar.externalCalendars.calendars) { source in
                        Toggle(isOn: Binding(get: {
                            env.calendar.externalCalendars.selectedCalendarIDs.contains(source.id)
                        }, set: { enabled in
                            env.calendar.externalCalendars.setCalendarEnabled(source.id, enabled: enabled)
                            env.calendar.refreshCalendars()
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                Text(source.source).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    if env.calendar.externalCalendars.calendars.isEmpty {
                        Text("No calendars found. Add an account in macOS Calendar, then refresh.")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    HStack {
                        Button("Refresh calendars") { env.calendar.refreshCalendars() }
                        Button("Disconnect") { env.calendar.externalCalendars.disconnect() }
                    }
                } else {
                    Button(isConnecting ? "Connecting…" : "Connect macOS calendars") {
                        isConnecting = true
                        Task {
                            await env.calendar.externalCalendars.requestAccess()
                            env.calendar.refreshCalendars()
                            isConnecting = false
                        }
                    }.disabled(isConnecting)
                }
                if let error = env.calendar.externalCalendars.error { Text(error).font(.caption).foregroundStyle(ListAccent.orange.color) }
            }
        }
        .formStyle(.grouped)
        .onAppear { preferences = env.calendar.preferences; hasLoaded = true }
        .onChange(of: preferences) { _, value in
            guard hasLoaded else { return }
            var safe = value
            safe.defaultEstimateMinutes = max(1, min(100_800, value.defaultEstimateMinutes))
            safe.horizonDays = 28
            env.calendar.updatePreferences(safe)
        }
        .sheet(isPresented: $showsOverride) { overrideEditor }
    }

    private var profile: AvailabilityProfile { preferences.profile(for: category) }
    private func changeProfile(_ change: (inout AvailabilityProfile) -> Void) {
        if category == .work { change(&preferences.work) } else { change(&preferences.personal) }
    }
    private func weeklyBinding(_ weekday: Int, breaks: Bool) -> Binding<[AvailabilityWindow]> {
        Binding(get: { (breaks ? profile.breaks : profile.weekly)[weekday] ?? [] }, set: { values in
            changeProfile { profile in
                if breaks { profile.breaks[weekday] = values } else { profile.weekly[weekday] = values }
            }
        })
    }
    private func windowSummary(_ values: [AvailabilityWindow]) -> String {
        if values.isEmpty { return "Unavailable" }
        return values.map { "\(minuteText($0.startMinute))–\(minuteText($0.endMinute))" }.joined(separator: ", ")
    }
    private func minuteText(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
    private var overrideEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(category.title) hours override").font(.headline)
                Spacer()
                Button("Cancel") { showsOverride = false }
            }
            DatePicker("Date", selection: $overrideDate, displayedComponents: .date)
            AvailabilityWindowsEditor(title: "Available", windows: $overrideWindows)
            AvailabilityWindowsEditor(title: "Breaks", windows: $overrideBreaks)
            Text(overrideWindows.isEmpty ? "This day will be unavailable." : "These hours replace the weekly schedule for this date.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            HStack {
                Spacer()
                Button("Save override") {
                    let day = Calendar.current.startOfDay(for: overrideDate)
                    changeProfile { profile in
                        profile.overrides.removeAll { $0.id == editingOverrideID || Calendar.current.isDate($0.date, inSameDayAs: day) }
                        profile.overrides.append(AvailabilityOverride(date: day, windows: overrideWindows, breaks: overrideBreaks))
                    }
                    showsOverride = false
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 480)
    }
}

private struct AvailabilityWindowsEditor: View {
    let title: String
    @Binding var windows: [AvailabilityWindow]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    windows.append(AvailabilityWindow(startMinute: title == "Breaks" ? 720 : 540, endMinute: title == "Breaks" ? 780 : 1020))
                } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(.borderless).font(.caption).accessibilityLabel("Add \(title.lowercased()) time")
            }
            ForEach(windows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    DatePicker("From", selection: dateBinding(index, end: false), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: dateBinding(index, end: true), displayedComponents: .hourAndMinute)
                    Button { windows.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("Remove \(title.lowercased()) time")
                }
            }
            if windows.isEmpty {
                Text(title == "Breaks" ? "No breaks" : "Unavailable").font(.caption).foregroundStyle(Theme.tertiaryText)
            }
        }.padding(.vertical, 5)
    }
    private func dateBinding(_ index: Int, end: Bool) -> Binding<Date> {
        Binding(get: {
            guard windows.indices.contains(index) else { return .now }
            let minute = end ? windows[index].endMinute : windows[index].startMinute
            return Calendar.current.date(byAdding: .minute, value: minute, to: Calendar.current.startOfDay(for: .now)) ?? .now
        }, set: { date in
            guard windows.indices.contains(index) else { return }
            let values = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minute = (values.hour ?? 0) * 60 + (values.minute ?? 0)
            if end {
                windows[index].endMinute = minute == 0 ? 1440 : max(windows[index].startMinute + 1, minute)
            } else {
                windows[index].startMinute = min(minute, 1439)
                windows[index].endMinute = max(windows[index].endMinute, windows[index].startMinute + 1)
            }
        })
    }
}
