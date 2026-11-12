import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(HealthKitManager.self) private var health
    @Environment(CoachStore.self) private var coach
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var dayPlans: [DayPlan]
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @AppStorage(SettingsKey.userName) private var userName = ""

    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }

    var body: some View {
        let today = week.first(where: \.isToday)
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CoachInsightsView()
                    } label: {
                        ReadinessCard(readiness: coach.report.readiness)
                    }
                    if let advice = coach.report.nutrition.advice, coach.report.nutrition.bodyWeightKg != nil {
                        Label(advice, systemImage: "fork.knife").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    todayCard(today)
                }

                LeaderboardNudgeSection()

                Section("Today's day") {
                    Picker("What's on today", selection: Binding(
                        get: { today?.kind ?? .free },
                        set: { setTodayKind($0) })) {
                        ForEach(DayKind.allCases) { k in Label(k.label, systemImage: k.symbol).tag(k) }
                    }
                }

                Section("Check-ins") {
                    checkInsList(todayKind: today?.kind)
                }

                Section {
                    healthGrid
                } header: {
                    Text("Today so far")
                } footer: {
                    if health.today.refreshedAt == nil {
                        Text("Connect Apple Health in Settings to see food, steps and sleep here.")
                    } else {
                        Text("Food comes from FatSecret or any app that writes to Apple Health.")
                    }
                }

                Section("This week") {
                    WeekPlanner(sessions: finished, dayPlans: dayPlans)
                }
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showSettings = true } label: { Image(systemName: "gear") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable {
                await health.refreshToday()
                await coach.refresh(context: context)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
        return userName.isEmpty ? part : "\(part), \(userName)"
    }

    @ViewBuilder
    private func todayCard(_ today: TrainingPlanner.DayPlanResult?) -> some View {
        if let active = sessions.first(where: { !$0.isFinished }) {
            Button { router.activeSession = active } label: {
                Label("Resume \(active.templateName)", systemImage: "play.circle.fill").font(.headline)
            }
        } else if let today, today.trained {
            let s = finished.first { Calendar.current.isDateInToday($0.startedAt) }
            VStack(alignment: .leading, spacing: 6) {
                Label("Trained today", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                if let s {
                    Text("\(s.templateName) · \(Int(s.duration / 60)) min · \(unit.format(kg: s.totalVolumeKg))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Recover: protein, water, sleep.").font(.subheadline)
            }
        } else if let today, let t = today.planned {
            TemplateCard(template: t, highlighted: true) {
                WorkoutStarter.start(t, context: context, router: router)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(today?.kind == .free || today == nil ? "Rest day" : "\(today!.kind.label): rest day",
                      systemImage: "bed.double.fill")
                    .font(.headline)
                if let next = week.first(where: { $0.day > Calendar.current.startOfDay(for: .now) && $0.planned != nil }), let t = next.planned {
                    Text("Next session: \(t.name) on \(next.day.formatted(.dateTime.weekday(.wide))).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    let t = TrainingPlanner.suggestedTemplate(finishedSessions: finished)
                    WorkoutStarter.start(t, context: context, router: router)
                } label: {
                    Label("Train anyway", systemImage: "dumbbell")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var week: [TrainingPlanner.DayPlanResult] {
        let kinds = Dictionary(dayPlans.map { ($0.day, $0.kind) }, uniquingKeysWith: { a, _ in a })
        return TrainingPlanner.plan(days: TrainingPlanner.week(), dayKinds: kinds, finishedSessions: finished)
    }

    @ViewBuilder
    private func checkInsList(todayKind: DayKind?) -> some View {
        let schedule = CheckInSchedule.load()
        let times = schedule.activeTimes(on: .now, dayKind: todayKind)
        if times.isEmpty {
            Text(schedule.enabled ? "No check-ins today." : "Check-ins are off.").foregroundStyle(.secondary)
        }
        ForEach(times) { t in
            let passed = t.date(on: .now) <= .now
            let handled = UserDefaults.standard.bool(forKey: CheckInScheduler.handledKey(for: t, on: .now))
            HStack {
                Image(systemName: handled ? "checkmark.circle.fill" : passed ? "bell.badge" : "clock")
                    .foregroundStyle(handled ? .green : passed ? Theme.blue : .secondary)
                Text(t.label).monospacedDigit()
                Text(t.slot.title).foregroundStyle(.secondary)
                Spacer()
                if passed && !handled {
                    Button("Open") { router.tab = .chat }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private var healthGrid: some View {
        let h = health.today
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("Food", h.dietaryKcal.map { "\(Int($0)) kcal" }, "fork.knife")
            metric("Protein", h.proteinG.map { p in
                coach.report.nutrition.proteinLowG.map { "\(Int(p)) / \(Int($0)) g" } ?? "\(Int(p)) g"
            }, "bolt.heart")
            metric("Steps", h.steps.map { $0.formatted(.number.precision(.fractionLength(0))) }, "figure.walk")
            metric("Sleep", h.sleepHoursLastNight.map { String(format: "%.1f h", $0) }, "bed.double")
            metric("Carbs / fat", (h.carbsG != nil || h.fatG != nil) ? "\(Int(h.carbsG ?? 0)) / \(Int(h.fatG ?? 0)) g" : nil, "chart.pie")
            metric("Active", h.activeEnergyKcal.map { "\(Int($0)) kcal" }, "flame")
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, _ value: String?, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "–").font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setTodayKind(_ kind: DayKind) {
        let day = Calendar.current.startOfDay(for: .now)
        if let existing = dayPlans.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            if kind == .free { context.delete(existing) } else { existing.kind = kind }
        } else if kind != .free {
            context.insert(DayPlan(day: day, kind: kind))
        }
        try? context.save()
        Task { await CheckInSync.reschedule(context: context) }
    }
}
