import SwiftUI
import SwiftData

struct CheckInSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var schedule = CheckInSchedule.load()
    @State private var newTime = Date.now
    @State private var permissionDenied = false

    private var presetSelection: Binding<Int> {
        Binding(
            get: {
                if case .preset(let n) = schedule.mode { return n }
                return 0
            },
            set: { n in
                if n == 0 {
                    if case .preset(let current) = schedule.mode {
                        // Start the custom list from the preset the user had.
                        schedule.customTimes = CheckInSchedule.presetTimes(current)
                    }
                    schedule.mode = .custom
                } else {
                    schedule.mode = .preset(n)
                }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Check-ins", isOn: $schedule.enabled)
                if permissionDenied {
                    Text("Notifications are off for this app. Turn them on in iOS Settings → Notifications.")
                        .font(.footnote).foregroundStyle(Theme.warn)
                }
            } footer: {
                Text("A reminder arrives at each time. When you open it, the coach writes a short check-in: sleep and today's plan in the morning, food and movement at midday, a wrap-up in the evening.")
            }

            if schedule.enabled {
                Section("How often") {
                    Picker("Check-ins per day", selection: presetSelection) {
                        Text("Once a day").tag(1)
                        Text("Twice a day").tag(2)
                        Text("3 times a day").tag(3)
                        Text("4 times a day").tag(4)
                        Text("Custom times").tag(0)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    if schedule.mode == .custom {
                        ForEach(schedule.customTimes.sorted()) { t in
                            HStack {
                                Text(t.label).monospacedDigit()
                                Text(t.slot.title).foregroundStyle(.secondary)
                                if schedule.isQuiet(t) {
                                    Spacer()
                                    Text("quiet hours").font(.caption).foregroundStyle(Theme.warn)
                                }
                            }
                        }
                        .onDelete { idx in
                            let sorted = schedule.customTimes.sorted()
                            let remove = Set(idx.map { sorted[$0] })
                            schedule.customTimes.removeAll { remove.contains($0) }
                        }
                        HStack {
                            DatePicker("Add a time", selection: $newTime, displayedComponents: .hourAndMinute)
                            Button {
                                let t = TimeOfDay(date: newTime)
                                if !schedule.customTimes.contains(t) { schedule.customTimes.append(t) }
                            } label: {
                                Image(systemName: "plus.circle.fill").font(.title2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Add time")
                        }
                    } else {
                        ForEach(schedule.times) { t in
                            HStack {
                                Text(t.label).monospacedDigit()
                                Text(t.slot.title).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Times")
                } footer: {
                    if schedule.mode == .custom { Text("Add as many times as you like. Swipe left to remove one.") }
                }

                Section {
                    Toggle("Quiet hours", isOn: $schedule.quietHoursEnabled)
                    if schedule.quietHoursEnabled {
                        DatePicker("From", selection: timeBinding(\.quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: timeBinding(\.quietEnd), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("No check-ins during quiet hours.")
                }

                Section {
                    WeekdayPicker(selection: $schedule.weekdays)
                    Toggle("Skip on 24h shift days", isOn: $schedule.muteOn24hShift)
                    Toggle("Skip on 12h shift days", isOn: $schedule.muteOn12hShift)
                } header: {
                    Text("Days")
                } footer: {
                    Text("Mark shift days on the Today or Train tab.")
                }
            }
        }
        .navigationTitle("Check-ins")
        .onChange(of: schedule) { _, new in
            new.save()
            Task {
                if new.enabled {
                    let granted = await CheckInScheduler.requestPermission()
                    permissionDenied = !granted
                }
                await CheckInSync.reschedule(context: context)
            }
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<CheckInSchedule, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { schedule[keyPath: keyPath].date(on: .now) },
            set: { schedule[keyPath: keyPath] = TimeOfDay(date: $0) })
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.userContext) private var userContext = ""
    @State private var checkInsPerDay = 2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                        Text("Your pocket trainer").font(.title.bold())
                        Text("A two-day full-body program, fast set logging, PRs, and a coach that checks in around your schedule.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("About you") {
                    TextField("First name", text: $userName)
                    Picker("Units", selection: $unit) {
                        ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Your week, goals, anything the coach should know", text: $userContext, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Picker("Check-ins per day", selection: $checkInsPerDay) {
                        Text("None").tag(0)
                        ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                    }
                } header: {
                    Text("Check-ins")
                } footer: {
                    Text("You can set exact times, quiet hours and shift days later in Settings.")
                }

                Section {
                    Text("Apple Health and the AI coach are optional. Set them up any time from Settings (gear on the Today tab). Everything else works right away.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { finish() }.bold()
                }
            }
        }
    }

    private func finish() {
        var schedule = CheckInSchedule.load()
        if checkInsPerDay == 0 {
            schedule.enabled = false
        } else {
            schedule.enabled = true
            schedule.mode = .preset(checkInsPerDay)
        }
        schedule.save()
        Task {
            if schedule.enabled { await CheckInScheduler.requestPermission() }
            await CheckInSync.reschedule(context: context)
        }
        hasOnboarded = true
        dismiss()
    }
}
