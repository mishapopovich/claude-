import SwiftUI
import SwiftData

struct SessionSummaryView: View {
    let session: WorkoutSession
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    var body: some View {
        let logic = SessionLogic(session: session, context: context)
        let records = logic.sessionRecords()
        NavigationStack {
            List {
                Section {
                    HStack {
                        stat("Duration", "\(Int(session.duration / 60)) min")
                        stat("Sets", "\(session.completedSets.count)")
                        stat("Volume", unit.format(kg: session.totalVolumeKg))
                    }
                    .listRowBackground(Color.clear)
                }

                if !records.isEmpty {
                    Section("New personal records") {
                        ForEach(Array(records.enumerated()), id: \.offset) { _, r in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                VStack(alignment: .leading) {
                                    Text(ExerciseCatalog.name(r.exerciseID)).font(.headline)
                                    Text(r.kind == .estimated1RM
                                         ? "Estimated 1RM \(unit.format(kg: r.set.estimatedOneRepMaxKg)) (\(unit.format(kg: r.set.weightKg, withUnit: false))×\(r.set.reps))"
                                         : "Heaviest set: \(unit.format(kg: r.set.weightKg))")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }

                Section("Exercises") {
                    ForEach(session.exerciseOrder, id: \.self) { exID in
                        let sets = session.sets(for: exID).filter { !$0.skipped }
                        if !sets.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ExerciseCatalog.name(exID)).font(.headline)
                                Text(sets.map { "\(unit.format(kg: $0.weightKg, withUnit: false))×\($0.reps)" }.joined(separator: "  ·  "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Label(session.savedToHealth ? "Saved to Apple Health" : "Saving to Apple Health if allowed in Settings",
                          systemImage: session.savedToHealth ? "checkmark.circle" : "heart")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(DefaultProgram.progressionRule)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(records.isEmpty ? "Workout done" : "Workout done. New PR!")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).bold()
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Searchable library picker used to add an exercise to a session.
struct ExercisePickerSheet: View {
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases) { cat in
                    let items = filtered.filter { $0.category == cat }
                    if !items.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(items) { ex in
                                Button {
                                    onPick(ex)
                                    dismiss()
                                } label: {
                                    ExerciseRow(exercise: ex)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var filtered: [Exercise] {
        LibraryView.filter(ExerciseCatalog.all, query: query)
    }
}
