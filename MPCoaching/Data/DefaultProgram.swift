import Foundation

struct PlannedExercise: Identifiable, Hashable {
    let exerciseID: String
    let sets: Int
    let repLow: Int
    let repHigh: Int
    var perSide: Bool = false
    var note: String? = nil
    /// Exercise to alternate with (superset / pairing), shown as a hint.
    var pairedWith: String? = nil

    var id: String { exerciseID }

    var repLabel: String {
        let reps = repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)"
        return perSide ? "\(reps) per leg" : reps
    }

    var prescription: String { "\(sets) × \(repLabel)" }

    var exercise: Exercise? { ExerciseCatalog.exercise(exerciseID) }
}

struct WorkoutTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let focus: String
    let exercises: [PlannedExercise]

    func planned(_ exerciseID: String) -> PlannedExercise? { exercises.first { $0.exerciseID == exerciseID } }
}

struct Program: Identifiable {
    let id: String
    let name: String
    let summary: String
    let templates: [WorkoutTemplate]
    let progressionRule: String

    func template(_ id: String?) -> WorkoutTemplate? {
        guard let id else { return nil }
        return templates.first { $0.id == id }
    }

    /// Alternate days: after Day 1 comes Day 2 and so on.
    func template(after id: String?) -> WorkoutTemplate {
        guard let id, let i = templates.firstIndex(where: { $0.id == id }) else { return templates[0] }
        return templates[(i + 1) % templates.count]
    }
}

enum DefaultProgram {
    static let progressionRule = "Each week, add a rep or two, or add 2.5–5 lb, or cut rest by 10–15 seconds. Start light, form first."

    static let fullBody = Program(
        id: "full-body-2x",
        name: "Two-day full body",
        summary: "Two ~30 minute sessions a week. Compound lifts, whole body both days. Built to fit around shifts and clinicals.",
        templates: [
            WorkoutTemplate(
                id: "fb-day-1", name: "Day 1", focus: "Push + pull focus",
                exercises: [
                    PlannedExercise(exerciseID: "barbell-back-squat", sets: 3, repLow: 8, repHigh: 12),
                    PlannedExercise(exerciseID: "lat-pulldown", sets: 3, repLow: 10, repHigh: 12),
                    PlannedExercise(exerciseID: "close-grip-dumbbell-bench-press", sets: 3, repLow: 8, repHigh: 10),
                    PlannedExercise(exerciseID: "romanian-deadlift", sets: 3, repLow: 8, repHigh: 12),
                    PlannedExercise(exerciseID: "overhead-dumbbell-press", sets: 3, repLow: 10, repHigh: 10,
                                    note: "Pair with goblet squats: alternate sets.", pairedWith: "goblet-squat"),
                    PlannedExercise(exerciseID: "goblet-squat", sets: 3, repLow: 10, repHigh: 10,
                                    note: "Paired with the overhead press.", pairedWith: "overhead-dumbbell-press"),
                ]),
            WorkoutTemplate(
                id: "fb-day-2", name: "Day 2", focus: "Opposite pairings + volume",
                exercises: [
                    PlannedExercise(exerciseID: "deadlift", sets: 3, repLow: 6, repHigh: 8),
                    PlannedExercise(exerciseID: "barbell-row", sets: 3, repLow: 10, repHigh: 10,
                                    note: "Superset with dumbbell bench press.", pairedWith: "dumbbell-bench-press"),
                    PlannedExercise(exerciseID: "dumbbell-bench-press", sets: 3, repLow: 10, repHigh: 10,
                                    note: "Superset with barbell rows.", pairedWith: "barbell-row"),
                    PlannedExercise(exerciseID: "lunge", sets: 3, repLow: 8, repHigh: 10, perSide: true),
                    PlannedExercise(exerciseID: "upright-row", sets: 3, repLow: 12, repHigh: 12,
                                    note: "Superset with seated shoulder press.", pairedWith: "seated-shoulder-press"),
                    PlannedExercise(exerciseID: "seated-shoulder-press", sets: 3, repLow: 10, repHigh: 10,
                                    note: "Superset with upright rows.", pairedWith: "upright-row"),
                ]),
        ],
        progressionRule: progressionRule)

    static let programs: [Program] = [fullBody]
    static var current: Program { fullBody }
}
