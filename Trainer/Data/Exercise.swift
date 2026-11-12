import Foundation

enum Equipment: String, CaseIterable, Codable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case kettlebell = "Kettlebell"
    case cable = "Cable"
    case machine = "Machine"
    case bodyweight = "Bodyweight"
    case bench = "Bench"
    case pullUpBar = "Pull-up bar"
}

enum ExerciseCategory: String, CaseIterable, Codable, Identifiable {
    case legs = "Legs"
    case push = "Push"
    case pull = "Pull"
    case arms = "Arms"
    case shoulders = "Shoulders"
    case core = "Core & carries"

    var id: String { rawValue }
}

/// A movement in the built-in library. The library is static app data (v1); logged sets refer to
/// exercises by `id`, so ids must never change once shipped.
struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let category: ExerciseCategory
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [Equipment]
    let steps: [String]
    let mistakes: [String]
    /// Which stick-figure animation to show when no photo is bundled.
    let pattern: MovementPattern
    /// Default weight jump for the +/- buttons, in pounds.
    let incrementLbs: Double
    /// Bodyweight moves log reps with optional added weight.
    var isBodyweight: Bool { equipment == [.bodyweight] || equipment == [.pullUpBar] }

    /// If an image with this name is added to Assets.xcassets it is shown instead of the drawing.
    var photoAssetName: String { "exercise-\(id)" }

    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum BigThree: String, CaseIterable, Identifiable {
    case bench, squat, deadlift

    var id: String { rawValue }

    var exerciseID: String {
        switch self {
        case .bench: "barbell-bench-press"
        case .squat: "barbell-back-squat"
        case .deadlift: "deadlift"
        }
    }

    var name: String {
        switch self {
        case .bench: "Bench press"
        case .squat: "Squat"
        case .deadlift: "Deadlift"
        }
    }
}
