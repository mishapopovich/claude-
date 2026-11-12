import SwiftUI
import SwiftData
import Charts

/// Bodyweight plus bench / squat / deadlift maxes and their total.
struct ProgressHubView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    // Observing all sets and records keeps the maxes live as sets are logged.
    @Query private var sets: [ExerciseSet]
    @Query private var records: [PersonalRecord]

    @State private var showLogWeight = false
    @State private var testedFor: BigThree?

    var body: some View {
        let maxes = Dictionary(uniqueKeysWithValues: BigThree.allCases.map { lift in
            (lift, PRService.currentMax(
                sets: sets.filter { $0.exerciseID == lift.exerciseID && !$0.skipped && $0.reps > 0 },
                tested: records.filter { $0.exerciseID == lift.exerciseID && $0.kind == .tested1RM }))
        })
        let total = maxes.values.compactMap { $0?.valueKg }.reduce(0, +)

        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text("Big three total").font(.subheadline).foregroundStyle(.secondary)
                        Text(total > 0 ? unit.format(kg: total) : "–")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        if maxes.values.contains(where: { $0 == nil }) {
                            Text("Log or enter all three lifts for a full total.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Bench · Squat · Deadlift") {
                    ForEach(BigThree.allCases) { lift in
                        NavigationLink {
                            LiftHistoryView(lift: lift)
                        } label: {
                            LiftRow(lift: lift, max: maxes[lift] ?? nil, unit: unit)
                        }
                        .swipeActions {
                            Button("Tested max") { testedFor = lift }.tint(.blue)
                        }
                    }
                    Menu {
                        ForEach(BigThree.allCases) { lift in
                            Button(lift.name) { testedFor = lift }
                        }
                    } label: {
                        Label("Enter a tested 1RM", systemImage: "checkmark.seal")
                    }
                }

                BodyWeightSection(weights: weights, unit: unit) { showLogWeight = true }

                Section {
                    NavigationLink {
                        AllStatsView()
                    } label: {
                        Label("Stats for every exercise", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            .navigationTitle("PRs")
            .sheet(isPresented: $showLogWeight) {
                LogWeightSheet(unit: unit)
                    .presentationDetents([.medium])
            }
            .sheet(item: $testedFor) { lift in
                TestedMaxSheet(lift: lift, unit: unit)
                    .presentationDetents([.medium])
            }
        }
    }
}

struct LiftRow: View {
    let lift: BigThree
    let max: PRService.CurrentMax?
    let unit: WeightUnit

    var body: some View {
        HStack {
            if let ex = ExerciseCatalog.exercise(lift.exerciseID) {
                ExercisePicture(exercise: ex, animated: false).frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name).font(.headline)
                if let max {
                    Text("\(max.kind == .tested1RM ? "Tested" : "Estimated from \(unit.format(kg: max.weightKg, withUnit: false))×\(max.reps)") · \(max.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data yet").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let max {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(unit.format(kg: max.valueKg)).font(.title3.bold()).monospacedDigit()
                    Text(max.kind == .tested1RM ? "tested" : "est. 1RM")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(max.kind == .tested1RM ? .blue : .orange)
                }
            }
        }
    }
}

/// History of a big-three lift's maxes, tested and estimated, with a chart.
struct LiftHistoryView: View {
    let lift: BigThree
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @State private var showTested = false
    @Query private var records: [PersonalRecord]

    init(lift: BigThree) {
        self.lift = lift
        let id = lift.exerciseID
        _records = Query(filter: #Predicate<PersonalRecord> { $0.exerciseID == id }, sort: \.date)
    }

    var body: some View {
        let sets = PRService.sets(for: lift.exerciseID, in: context)
        let tested = records.filter { $0.kind == .tested1RM }
        let events = PRService.timeline(sets: sets, tested: tested).filter { $0.kind != .heaviestWeight }
        List {
            if events.count >= 2 {
                Section("Max over time") {
                    Chart(events) { e in
                        LineMark(x: .value("Date", e.date), y: .value("Max", unit.fromKg(e.valueKg)))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(by: .value("Kind", e.kind == .tested1RM ? "Tested" : "Estimated"))
                        PointMark(x: .value("Date", e.date), y: .value("Max", unit.fromKg(e.valueKg)))
                            .foregroundStyle(by: .value("Kind", e.kind == .tested1RM ? "Tested" : "Estimated"))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                }
            }
            Section("Past maxes") {
                if events.isEmpty {
                    Text("Log \(lift.name.lowercased()) sets in a workout, or enter a tested 1RM.").foregroundStyle(.secondary)
                }
                ForEach(Array(events.reversed())) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.kind == .tested1RM ? "Tested 1RM" : "Estimated 1RM").font(.subheadline.weight(.semibold))
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
            if !tested.isEmpty {
                Section("Tested entries") {
                    ForEach(tested) { r in
                        LabeledContent(r.date.formatted(date: .abbreviated, time: .omitted), value: unit.format(kg: r.weightKg))
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(tested[i]) }
                        try? context.save()
                    }
                }
            }
            Section {
                Button { showTested = true } label: { Label("Enter a tested 1RM", systemImage: "checkmark.seal") }
                if let ex = ExerciseCatalog.exercise(lift.exerciseID) {
                    NavigationLink("All \(lift.name.lowercased()) stats") { ExerciseStatsView(exercise: ex) }
                }
            }
        }
        .navigationTitle(lift.name)
        .sheet(isPresented: $showTested) {
            TestedMaxSheet(lift: lift, unit: unit).presentationDetents([.medium])
        }
    }
}

struct BodyWeightSection: View {
    let weights: [BodyWeightEntry]
    let unit: WeightUnit
    var onLog: () -> Void
    @State private var range: StatsRange = .threeMonths
    @Environment(\.modelContext) private var context

    /// Trailing 7-day average at each weigh-in, so one noisy reading doesn't dominate.
    private func weeklyAverage(at date: Date) -> Double? {
        let window = weights.filter { $0.date <= date && $0.date > date.addingTimeInterval(-7 * 86_400) }
        guard !window.isEmpty else { return nil }
        return window.map(\.weightKg).reduce(0, +) / Double(window.count)
    }

    var body: some View {
        let visible = weights.filter { range.startDate == nil || $0.date >= range.startDate! }
        Section {
            if let latest = weights.last {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Latest").font(.caption).foregroundStyle(.secondary)
                        Text(unit.format(kg: latest.weightKg)).font(.title2.bold()).monospacedDigit()
                        Text(latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let avg = weeklyAverage(at: .now) {
                        VStack(alignment: .trailing) {
                            Text("7-day average").font(.caption).foregroundStyle(.secondary)
                            Text(unit.format(kg: avg)).font(.title2.bold()).monospacedDigit()
                            Text("trend to watch").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if visible.count >= 2 {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Chart {
                        ForEach(visible) { w in
                            PointMark(x: .value("Date", w.date), y: .value("Weight", unit.fromKg(w.weightKg)))
                                .foregroundStyle(.gray.opacity(0.6))
                                .symbolSize(20)
                        }
                        ForEach(visible) { w in
                            if let avg = weeklyAverage(at: w.date) {
                                LineMark(x: .value("Date", w.date), y: .value("7-day avg", unit.fromKg(avg)))
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    Text("Dots are single weigh-ins; the line is the 7-day average.").font(.caption2).foregroundStyle(.secondary)
                }
                DisclosureGroup("All weigh-ins") {
                    ForEach(weights.reversed()) { w in
                        HStack {
                            Text(w.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            if w.source == .healthKit { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
                            Text(unit.format(kg: w.weightKg)).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    .onDelete { idx in
                        let reversed = Array(weights.reversed())
                        for i in idx { context.delete(reversed[i]) }
                        try? context.save()
                    }
                }
            } else {
                Text("Log your weight here, or allow body weight in Settings → Apple Health to import it from a scale.")
                    .foregroundStyle(.secondary)
            }
            Button(action: onLog) { Label("Log weight", systemImage: "plus.circle") }
        } header: {
            Text("Body weight")
        } footer: {
            Text("Private. Body weight is never shared with friends or shown on a leaderboard.")
        }
    }
}

struct LogWeightSheet: View {
    let unit: WeightUnit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @State private var value: Double = 0
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Weight", value: $value, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(unit.rawValue).font(.title2).foregroundStyle(.secondary)
                }
                DatePicker("When", selection: $date, in: ...Date.now)
                Text("Saved to Apple Health too, if you allowed body weight.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let kg = unit.toKg(value)
                        context.insert(BodyWeightEntry(date: date, weightKg: kg, source: .manual))
                        try? context.save()
                        Task { await HealthKitManager.shared.saveBodyMass(kg: kg, date: date) }
                        dismiss()
                    }
                    .disabled(value <= 0)
                }
            }
            .onAppear {
                if let last = weights.first { value = (unit.fromKg(last.weightKg) * 10).rounded() / 10 }
            }
        }
    }
}

struct TestedMaxSheet: View {
    let lift: BigThree
    let unit: WeightUnit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var value: Double = 0
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", value: $value, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(unit.rawValue).font(.title2).foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("A tested max is a single rep you actually completed. It's labelled \"tested\" so it's never confused with an estimate.")
                }
            }
            .navigationTitle("Tested \(lift.name.lowercased()) 1RM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let kg = unit.toKg(value)
                        let previous = PRService.currentMax(for: lift, in: context)
                        context.insert(PersonalRecord(exerciseID: lift.exerciseID, kind: .tested1RM, weightKg: kg, reps: 1, date: date))
                        try? context.save()
                        if let previous, kg > previous.valueKg + 0.01 {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        dismiss()
                    }
                    .disabled(value <= 0)
                }
            }
        }
    }
}
