import Foundation
import SwiftData

/// Personal-record logic. Estimated and heaviest-weight PRs are derived from logged sets every
/// time (so editing or deleting a set can never leave a stale record). Tested maxes are stored
/// as `PersonalRecord` rows because they are typed in by the user.
enum PRService {
    struct PREvent: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let kind: PRKind
        let weightKg: Double
        let reps: Int
        /// The ranking value: 1RM (estimated or tested) or the raw weight.
        let valueKg: Double
    }

    struct CurrentMax {
        let valueKg: Double
        let date: Date
        let kind: PRKind   // .tested1RM or .estimated1RM
        let weightKg: Double
        let reps: Int
    }

    // MARK: Fetching

    static func sets(for exerciseID: String, in context: ModelContext) -> [ExerciseSet] {
        let id = exerciseID
        let descriptor = FetchDescriptor<ExerciseSet>(
            predicate: #Predicate { $0.exerciseID == id && $0.skipped == false && $0.reps > 0 },
            sortBy: [SortDescriptor(\.completedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func testedMaxes(for exerciseID: String, in context: ModelContext) -> [PersonalRecord] {
        let id = exerciseID
        let tested = PRKind.tested1RM.rawValue
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseID == id && $0.kindRaw == tested },
            sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Derived records

    /// Every moment a new best was set, oldest first.
    static func timeline(sets: [ExerciseSet], tested: [PersonalRecord] = []) -> [PREvent] {
        var events: [PREvent] = []
        var bestE1RM = 0.0
        var bestWeight = 0.0
        for s in sets.sorted(by: { $0.completedAt < $1.completedAt }) where !s.skipped && s.reps > 0 && s.weightKg > 0 {
            let e = s.estimatedOneRepMaxKg
            if e > bestE1RM + 0.01 {
                bestE1RM = e
                events.append(PREvent(date: s.completedAt, kind: .estimated1RM, weightKg: s.weightKg, reps: s.reps, valueKg: e))
            }
            if s.weightKg > bestWeight + 0.01 {
                bestWeight = s.weightKg
                events.append(PREvent(date: s.completedAt, kind: .heaviestWeight, weightKg: s.weightKg, reps: s.reps, valueKg: s.weightKg))
            }
        }
        for t in tested {
            events.append(PREvent(date: t.date, kind: .tested1RM, weightKg: t.weightKg, reps: 1, valueKg: t.weightKg))
        }
        return events.sorted { $0.date < $1.date }
    }

    /// Which records a just-logged set beats. Empty when this is the first time the exercise is
    /// logged (the first session sets a baseline; celebrating it would be noise).
    static func newRecords(for set: ExerciseSet, previous: [ExerciseSet]) -> [PRKind] {
        let prior = previous.filter { $0.id != set.id && !$0.skipped && $0.reps > 0 && $0.completedAt <= set.completedAt }
        guard !set.skipped, set.reps > 0, set.weightKg > 0 else { return [] }
        // Only celebrate once there is history from an earlier session.
        let hasEarlierSession = prior.contains { $0.session?.id != set.session?.id }
        guard hasEarlierSession else { return [] }
        var kinds: [PRKind] = []
        let bestE = prior.map(\.estimatedOneRepMaxKg).max() ?? 0
        let bestW = prior.map(\.weightKg).max() ?? 0
        if set.estimatedOneRepMaxKg > bestE + 0.01 { kinds.append(.estimated1RM) }
        if set.weightKg > bestW + 0.01 { kinds.append(.heaviestWeight) }
        return kinds
    }

    /// The headline max for a lift: the higher of the best tested 1RM and the best estimated 1RM.
    static func currentMax(sets: [ExerciseSet], tested: [PersonalRecord]) -> CurrentMax? {
        let bestSet = sets.filter { !$0.skipped && $0.reps > 0 }.max { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }
        let bestTested = tested.max { $0.weightKg < $1.weightKg }
        let est = bestSet.map { CurrentMax(valueKg: $0.estimatedOneRepMaxKg, date: $0.completedAt, kind: .estimated1RM, weightKg: $0.weightKg, reps: $0.reps) }
        let tst = bestTested.map { CurrentMax(valueKg: $0.weightKg, date: $0.date, kind: .tested1RM, weightKg: $0.weightKg, reps: 1) }
        switch (est, tst) {
        case let (e?, t?): return t.valueKg >= e.valueKg ? t : e
        case let (e?, nil): return e
        case let (nil, t?): return t
        default: return nil
        }
    }

    static func currentMax(for lift: BigThree, in context: ModelContext) -> CurrentMax? {
        currentMax(sets: sets(for: lift.exerciseID, in: context), tested: testedMaxes(for: lift.exerciseID, in: context))
    }
}
