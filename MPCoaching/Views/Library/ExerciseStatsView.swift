import SwiftUI
import SwiftData
import Charts

enum StatsRange: String, CaseIterable, Identifiable {
    case month = "1M", threeMonths = "3M", sixMonths = "6M", all = "All"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .month: return cal.date(byAdding: .month, value: -1, to: .now)
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: .now)
        case .sixMonths: return cal.date(byAdding: .month, value: -6, to: .now)
        case .all: return nil
        }
    }
}

/// Per-exercise progress: best weight, estimated 1RM over time (Epley), volume over time,
/// recent sessions and every PR.
struct ExerciseStatsView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @State private var range: StatsRange = .threeMonths
    @Query private var allSets: [ExerciseSet]
    @Query private var allRecords: [PersonalRecord]

    init(exercise: Exercise) {
        self.exercise = exercise
        let id = exercise.id
        _allSets = Query(filter: #Predicate<ExerciseSet> { $0.exerciseID == id && $0.skipped == false && $0.reps > 0 },
                         sort: \.completedAt)
        let tested = PRKind.tested1RM.rawValue
        _allRecords = Query(filter: #Predicate<PersonalRecord> { $0.exerciseID == id && $0.kindRaw == tested },
                            sort: \.date)
    }

    /// One point per session (keyed by the session's day).
    struct SessionPoint: Identifiable {
        let id: String
        let date: Date
        let bestE1RMKg: Double
        let topWeightKg: Double
        let volumeKg: Double
        let sets: [ExerciseSet]
    }

    private var sessionPoints: [SessionPoint] {
        let grouped = Dictionary(grouping: allSets) { s -> String in
            s.session?.id.uuidString ?? Calendar.current.startOfDay(for: s.completedAt).description
        }
        return grouped.compactMap { key, sets -> SessionPoint? in
            guard let first = sets.min(by: { $0.completedAt < $1.completedAt }) else { return nil }
            return SessionPoint(
                id: key,
                date: first.completedAt,
                bestE1RMKg: sets.map(\.estimatedOneRepMaxKg).max() ?? 0,
                topWeightKg: sets.map(\.weightKg).max() ?? 0,
                volumeKg: sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) },
                sets: sets.sorted { $0.setNumber < $1.setNumber })
        }
        .sorted { $0.date < $1.date }
    }

    private var visiblePoints: [SessionPoint] {
        guard let start = range.startDate else { return sessionPoints }
        return sessionPoints.filter { $0.date >= start }
    }

    var body: some View {
        let points = sessionPoints
        let visible = visiblePoints
        let best = PRService.currentMax(sets: allSets, tested: allRecords)
        List {
            Section {
                HStack {
                    statTile("Best weight", allSets.map(\.weightKg).max().map { unit.format(kg: $0) } ?? "–")
                    statTile(best?.kind == .tested1RM ? "Tested 1RM" : "Est. 1RM", best.map { unit.format(kg: $0.valueKg) } ?? "–")
                    statTile("Sessions", "\(points.count)")
                }
                .listRowBackground(Color.clear)
            }

            if points.count < 2 {
                Section {
                    ContentUnavailableView(
                        "Not enough history yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text(points.isEmpty
                                          ? "Log \(exercise.name) in a workout and your progress shows up here."
                                          : "One session logged. After the next one you'll see a trend line."))
                }
            } else {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    chartTitle("Estimated 1RM (Epley)")
                    Chart(visible) { p in
                        LineMark(x: .value("Date", p.date), y: .value("1RM", unit.fromKg(p.bestE1RMKg)))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value("1RM", unit.fromKg(p.bestE1RMKg)))
                            .symbolSize(30)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    .overlay { if visible.isEmpty { Text("No sessions in this range").foregroundStyle(.secondary) } }

                    chartTitle("Volume per session (\(unit.rawValue))")
                    Chart(visible) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Volume", unit.fromKg(p.volumeKg)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.blue.opacity(0.6))
                        PointMark(x: .value("Date", p.date), y: .value("Volume", unit.fromKg(p.volumeKg)))
                            .foregroundStyle(Theme.blue.opacity(0.6))
                            .symbolSize(30)
                    }
                    .frame(height: 160)
                }
            }

            let timeline = PRService.timeline(sets: allSets, tested: allRecords)
            if !timeline.isEmpty {
                Section("Personal records") {
                    ForEach(Array(timeline.reversed())) { e in
                        HStack {
                            Image(systemName: e.kind == .tested1RM ? "checkmark.seal.fill" : "trophy")
                                .foregroundStyle(e.kind == .tested1RM ? Theme.blue : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(e.kind.label).font(.subheadline.weight(.semibold))
                                Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(unit.format(kg: e.valueKg)).font(.headline).monospacedDigit()
                                if e.kind == .estimated1RM {
                                    Text("from \(unit.format(kg: e.weightKg, withUnit: false))×\(e.reps)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if !points.isEmpty {
                Section("Recent sessions") {
                    ForEach(Array(points.reversed().prefix(10))) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                            Text(p.sets.map { "\(unit.format(kg: $0.weightKg, withUnit: false))×\($0.reps)" }.joined(separator: "  ·  "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink("How to do \(exercise.name)") { ExerciseDetailView(exercise: exercise) }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chartTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).listRowSeparator(.hidden)
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

/// Every exercise the user has logged, most recent first. Reached from the PRs tab.
struct AllStatsView: View {
    @Query(sort: \ExerciseSet.completedAt, order: .reverse) private var sets: [ExerciseSet]

    var body: some View {
        let ids = sets.filter { !$0.skipped }.map(\.exerciseID).reduce(into: [String]()) { acc, id in
            if !acc.contains(id) { acc.append(id) }
        }
        List {
            if ids.isEmpty {
                ContentUnavailableView("No lifts logged yet", systemImage: "chart.bar", description: Text("Finish a workout and every exercise gets its own stats page."))
            }
            ForEach(ids, id: \.self) { id in
                if let ex = ExerciseCatalog.exercise(id) {
                    NavigationLink { ExerciseStatsView(exercise: ex) } label: { ExerciseRow(exercise: ex) }
                }
            }
        }
        .navigationTitle("Exercise stats")
    }
}
