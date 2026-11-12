import SwiftUI
import SwiftData

@MainActor
enum WorkoutStarter {
    /// Starts a session from a template (or a free session), or resumes the one already in progress.
    static func start(_ template: WorkoutTemplate?, context: ModelContext, router: AppRouter) {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt == nil })
        if let active = try? context.fetch(descriptor).first {
            router.activeSession = active
            return
        }
        let session = WorkoutSession(
            templateID: template?.id,
            templateName: template.map { "\($0.name) · \($0.focus)" } ?? "Free session",
            exerciseOrder: template?.exercises.map(\.exerciseID) ?? [])
        // Adjust the plan to today's readiness (the user can switch back to the full plan).
        let readiness = CoachStore.shared.report.readiness
        session.readinessAtStart = readiness.score
        session.setAdjustment = readiness.level.setAdjustment
        context.insert(session)
        try? context.save()
        router.activeSession = session
    }
}

struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var dayPlans: [DayPlan]
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    private var finished: [WorkoutSession] { sessions.filter(\.isFinished) }
    private var active: WorkoutSession? { sessions.first { !$0.isFinished } }

    var body: some View {
        NavigationStack {
            List {
                if let active {
                    Section {
                        Button {
                            router.activeSession = active
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill").font(.largeTitle)
                                VStack(alignment: .leading) {
                                    Text("Resume workout").font(.headline)
                                    Text("\(active.templateName) · \(active.completedSets.count) sets logged")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Up next") {
                    let next = TrainingPlanner.suggestedTemplate(finishedSessions: finished)
                    TemplateCard(template: next, highlighted: true) {
                        WorkoutStarter.start(next, context: context, router: router)
                    }
                }

                Section {
                    WeekPlanner(sessions: finished, dayPlans: dayPlans)
                } header: {
                    Text("This week")
                } footer: {
                    Text("Tap a day to mark shifts, clinicals or classes. Sessions move to the best free days, with a rest day between when possible.")
                }

                Section {
                    NavigationLink {
                        LibraryView(embedded: true)
                    } label: {
                        Label("Exercise library", systemImage: "books.vertical")
                    }
                }

                Section(DefaultProgram.current.name) {
                    Text(DefaultProgram.current.summary).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(DefaultProgram.current.templates) { t in
                        NavigationLink {
                            TemplateDetailView(template: t)
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(t.name) · \(t.focus)").font(.headline)
                                Text(t.exercises.compactMap { $0.exercise?.name }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    Button {
                        WorkoutStarter.start(nil, context: context, router: router)
                    } label: {
                        Label("Start a free session", systemImage: "plus.circle")
                    }
                    Label(DefaultProgram.progressionRule, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("History") {
                    if finished.isEmpty {
                        Text("Finished workouts show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(finished) { s in
                        NavigationLink {
                            SessionDetailView(session: s)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.templateName).font(.headline)
                                Text("\(s.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(s.duration / 60)) min · \(unit.format(kg: s.totalVolumeKg))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(finished[i]) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Train")
        }
    }
}

struct TemplateCard: View {
    let template: WorkoutTemplate
    var highlighted = false
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(template.name) · \(template.focus)").font(.title3.bold())
            ForEach(template.exercises) { p in
                HStack {
                    if let ex = p.exercise {
                        ExercisePicture(exercise: ex, animated: false).frame(width: 34, height: 34)
                    }
                    Text(p.exercise?.name ?? p.exerciseID)
                    Spacer()
                    Text(p.prescription).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.subheadline)
            }
            Button(action: onStart) {
                Label("Start \(template.name)", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}

struct TemplateDetailView: View {
    let template: WorkoutTemplate
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section {
                TemplateCard(template: template) {
                    WorkoutStarter.start(template, context: context, router: router)
                }
            }
            Section("Exercises") {
                ForEach(template.exercises) { p in
                    if let ex = p.exercise {
                        NavigationLink {
                            ExerciseDetailView(exercise: ex)
                        } label: {
                            VStack(alignment: .leading) {
                                ExerciseRow(exercise: ex)
                                if let note = p.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: session.startedAt.formatted(date: .complete, time: .shortened))
                LabeledContent("Duration", value: "\(Int(session.duration / 60)) min")
                LabeledContent("Total volume", value: unit.format(kg: session.totalVolumeKg))
                if session.savedToHealth { Label("Saved to Apple Health", systemImage: "heart.fill").foregroundStyle(.pink) }
            }
            ForEach(session.exerciseOrder, id: \.self) { exID in
                let sets = session.sets(for: exID)
                if !sets.isEmpty {
                    Section {
                        ForEach(sets) { s in
                            HStack {
                                Text("Set \(s.setNumber)")
                                Spacer()
                                if s.skipped {
                                    Text("Skipped").foregroundStyle(.secondary)
                                } else {
                                    Text("\(unit.format(kg: s.weightKg)) × \(s.reps)").monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        if let ex = ExerciseCatalog.exercise(exID) {
                            NavigationLink(ex.name) { ExerciseStatsView(exercise: ex) }
                        } else {
                            Text(exID)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.templateName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Seven-day strip: tap a day to say what's on (shift, clinical, class) and see where sessions land.
struct WeekPlanner: View {
    let sessions: [WorkoutSession]
    let dayPlans: [DayPlan]
    @Environment(\.modelContext) private var context

    var body: some View {
        let kinds = Dictionary(dayPlans.map { ($0.day, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let plan = TrainingPlanner.plan(days: TrainingPlanner.week(), dayKinds: kinds, finishedSessions: sessions)
        HStack(spacing: 4) {
            ForEach(plan) { d in
                Menu {
                    ForEach(DayKind.allCases) { k in
                        Button {
                            setKind(k, for: d.day)
                        } label: {
                            Label(k.label, systemImage: k.symbol)
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(d.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(d.isToday ? Color.accentColor : .secondary)
                        Image(systemName: d.kind.symbol).font(.caption)
                        Group {
                            if d.trained {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if let t = d.planned {
                                Text(t.name.replacingOccurrences(of: "Day ", with: "D"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            } else {
                                Text("rest").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 18)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(RoundedRectangle(cornerRadius: 8).fill(d.isToday ? Color.accentColor.opacity(0.08) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText(d))
            }
        }
    }

    private func accessibilityText(_ d: TrainingPlanner.DayPlanResult) -> String {
        var text = d.day.formatted(.dateTime.weekday(.wide)) + ": " + d.kind.label
        if d.trained {
            text += ", trained"
        } else if let t = d.planned {
            text += ", planned " + t.name
        }
        return text
    }

    private func setKind(_ kind: DayKind, for day: Date) {
        if let existing = dayPlans.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            if kind == .free { context.delete(existing) } else { existing.kind = kind }
        } else if kind != .free {
            context.insert(DayPlan(day: day, kind: kind))
        }
        try? context.save()
        Task { await CheckInSync.reschedule(context: context) }
    }
}
