import Foundation
import SwiftData

/// Pure helpers for the guided session, kept out of the view so the flow is easy to follow.
@MainActor
struct SessionLogic {
    let session: WorkoutSession
    let context: ModelContext

    var template: WorkoutTemplate? { DefaultProgram.current.template(session.templateID) }

    func planned(_ exerciseID: String) -> PlannedExercise? { template?.planned(exerciseID) }

    /// Planned number of sets; added exercises default to 3 (or however many were logged).
    func plannedSetCount(_ exerciseID: String) -> Int {
        planned(exerciseID)?.sets ?? 3
    }

    func logged(_ exerciseID: String) -> [ExerciseSet] { session.sets(for: exerciseID) }

    func remaining(_ exerciseID: String) -> Int { max(0, plannedSetCount(exerciseID) - logged(exerciseID).count) }

    func isDone(_ exerciseID: String) -> Bool { remaining(exerciseID) == 0 }

    var allDone: Bool { session.exerciseOrder.allSatisfy(isDone) }

    /// Where to go after logging a set: alternate with a paired exercise, otherwise stay until the
    /// planned sets are done, then move to the next unfinished exercise.
    func nextExercise(after current: String) -> String? {
        if let partner = planned(current)?.pairedWith, session.exerciseOrder.contains(partner), remaining(partner) > 0,
           logged(partner).count <= logged(current).count {
            return partner
        }
        if remaining(current) > 0 { return current }
        let order = session.exerciseOrder
        guard let i = order.firstIndex(of: current) else { return order.first(where: { !isDone($0) }) }
        let rotated = Array(order[(i + 1)...]) + Array(order[..<i])
        return rotated.first(where: { !isDone($0) })
    }

    /// Sets from the most recent earlier session that included this exercise.
    func lastTime(_ exerciseID: String) -> [ExerciseSet] {
        let all = PRService.sets(for: exerciseID, in: context)
        let earlier = all.filter { $0.session?.id != session.id && $0.completedAt < session.startedAt }
        guard let lastSessionID = earlier.max(by: { $0.completedAt < $1.completedAt })?.session?.id else { return [] }
        return earlier.filter { $0.session?.id == lastSessionID }.sorted { $0.setNumber < $1.setNumber }
    }

    /// Pre-fill for the next set: the previous set today, else the same set number last time, else last time's first set.
    func prefill(_ exerciseID: String, unit: WeightUnit) -> (weight: Double, reps: Int) {
        let today = logged(exerciseID).filter { !$0.skipped }
        if let last = today.last { return (unit.fromKg(last.weightKg), last.reps) }
        let prev = lastTime(exerciseID)
        let setNumber = logged(exerciseID).count + 1
        if let match = prev.first(where: { $0.setNumber == setNumber }) ?? prev.first {
            return (unit.fromKg(match.weightKg), match.reps)
        }
        let reps = planned(exerciseID)?.repHigh ?? 10
        return (0, reps)
    }

    /// If every set last time reached the top of the rep range, suggest a small weight increase.
    func progressionHint(_ exerciseID: String, unit: WeightUnit) -> Double? {
        guard let plan = planned(exerciseID) else { return nil }
        let prev = lastTime(exerciseID).filter { !$0.skipped }
        guard prev.count >= plan.sets, prev.allSatisfy({ $0.reps >= plan.repHigh }),
              let w = prev.map(\.weightKg).max(), w > 0 else { return nil }
        let step = unit == .kg ? 2.5 : (ExerciseCatalog.exercise(exerciseID)?.incrementLbs ?? 5)
        return unit.fromKg(w) + step
    }

    /// PRs set during this session (compared with everything before it).
    func sessionRecords() -> [(exerciseID: String, kind: PRKind, set: ExerciseSet)] {
        var out: [(String, PRKind, ExerciseSet)] = []
        for exID in session.exerciseOrder {
            let mine = logged(exID).filter { !$0.skipped && $0.reps > 0 && $0.weightKg > 0 }
            guard !mine.isEmpty else { continue }
            let before = PRService.sets(for: exID, in: context).filter { $0.session?.id != session.id && $0.completedAt < session.startedAt }
            guard !before.isEmpty else { continue }
            let bestE = before.map(\.estimatedOneRepMaxKg).max() ?? 0
            let bestW = before.map(\.weightKg).max() ?? 0
            if let top = mine.max(by: { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }), top.estimatedOneRepMaxKg > bestE + 0.01 {
                out.append((exID, .estimated1RM, top))
            }
            if let heavy = mine.max(by: { $0.weightKg < $1.weightKg }), heavy.weightKg > bestW + 0.01 {
                out.append((exID, .heaviestWeight, heavy))
            }
        }
        return out.map { (exerciseID: $0.0, kind: $0.1, set: $0.2) }
    }
}
