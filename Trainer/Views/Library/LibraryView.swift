import SwiftUI
import SwiftData

struct LibraryView: View {
    @State private var query = ""
    @State private var category: ExerciseCategory?

    static func filter(_ list: [Exercise], query: String) -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { ex in
            ex.name.lowercased().contains(q)
                || ex.primaryMuscles.contains { $0.lowercased().contains(q) }
                || ex.secondaryMuscles.contains { $0.lowercased().contains(q) }
                || ex.equipment.contains { $0.rawValue.lowercased().contains(q) }
        }
    }

    private var results: [Exercise] {
        Self.filter(ExerciseCatalog.all, query: query).filter { category == nil || $0.category == category }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip("All", selected: category == nil) { category = nil }
                            ForEach(ExerciseCategory.allCases) { c in
                                chip(c.rawValue, selected: category == c) { category = c }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                ForEach(ExerciseCategory.allCases) { cat in
                    let items = results.filter { $0.category == cat }
                    if !items.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(items) { ex in
                                NavigationLink {
                                    ExerciseDetailView(exercise: ex)
                                } label: {
                                    ExerciseRow(exercise: ex)
                                }
                            }
                        }
                    }
                }
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Exercise, muscle or equipment")
            .navigationTitle("Library")
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExercisePicture(exercise: exercise, animated: false)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.body.weight(.medium))
                Text(exercise.primaryMuscles.joined(separator: ", ") + " · " + exercise.equipment.map(\.rawValue).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    var body: some View {
        let sets = PRService.sets(for: exercise.id, in: context)
        let best = PRService.currentMax(sets: sets, tested: PRService.testedMaxes(for: exercise.id, in: context))
        List {
            Section {
                ExercisePicture(exercise: exercise)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .listRowBackground(Color(.secondarySystemBackground))
            }

            Section {
                NavigationLink {
                    ExerciseStatsView(exercise: exercise)
                } label: {
                    HStack {
                        Label("Stats and history", systemImage: "chart.xyaxis.line")
                        Spacer()
                        if let best {
                            Text("1RM \(unit.format(kg: best.valueKg))").foregroundStyle(.secondary)
                        } else if !sets.isEmpty {
                            Text("\(sets.count) sets").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Muscles") {
                LabeledContent("Primary", value: exercise.primaryMuscles.joined(separator: ", "))
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Secondary", value: exercise.secondaryMuscles.joined(separator: ", "))
                }
                LabeledContent("Equipment", value: exercise.equipment.map(\.rawValue).joined(separator: ", "))
            }

            Section("How to do it") {
                ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.subheadline.bold())
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor.opacity(0.2)))
                        Text(step)
                    }
                }
            }

            Section("Common mistakes") {
                ForEach(exercise.mistakes, id: \.self) { m in
                    Label(m, systemImage: "exclamationmark.triangle")
                        .symbolRenderingMode(.multicolor)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
