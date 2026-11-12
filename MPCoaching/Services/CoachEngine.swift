import Foundation
import SwiftData
import HealthKit
import Observation

/// The "coach brain": looks at every metric the app has and decides how hard to push today.
///
/// It is rules-based and fully on-device (works with no API key). The AI chat receives the same
/// report so its advice matches what the app shows.
///
/// Science-based principles it follows (general sports-science consensus, not medical advice):
/// - Progressive overload when recovered; back off when recovery markers are down.
/// - Sleep, resting heart rate, sudden jumps in training load and stalled performance are the
///   main fatigue signals. Several of them together matter more than any single one.
/// - Weekly hard sets per muscle sit in a productive range; very low maintains, very high
///   outpaces recovery. A lighter "deload" week every 4–8 hard weeks lets fatigue drop.
/// - Protein around 1.6–2.2 g per kg of body weight; calories set from measured maintenance.
struct CoachReport {
    var readiness: Readiness
    var volume: [MuscleVolume]
    var load: TrainingLoad
    var nutrition: NutritionTargets
    var generatedAt = Date.now

    static let empty = CoachReport(
        readiness: Readiness(score: 75, factors: []),
        volume: [], load: TrainingLoad(acuteKg: 0, chronicWeeklyKg: 0, hardWeeksInARow: 0),
        nutrition: NutritionTargets())
}

// MARK: - Readiness

struct Readiness {
    struct Factor: Identifiable {
        let id = UUID()
        let text: String
        /// Points added to (or taken from) the score.
        let impact: Int
    }

    enum Level: String {
        case push, normal, easy, recover

        var title: String {
            switch self {
            case .push: "Green light"
            case .normal: "Normal day"
            case .easy: "Take it easier"
            case .recover: "Recovery day"
            }
        }

        var advice: String {
            switch self {
            case .push: "You're well recovered. Go for a rep or weight PR on your main lifts."
            case .normal: "Train as planned. Beat last time by a rep where it feels solid."
            case .easy: "Same weights, one set fewer per exercise, stop 2–3 reps before failure."
            case .recover: "Light session at about half the volume, or rest. Walk, eat protein, sleep."
            }
        }

        var symbol: String {
            switch self {
            case .push: "bolt.fill"
            case .normal: "checkmark.circle.fill"
            case .easy: "tortoise.fill"
            case .recover: "bed.double.fill"
            }
        }

        /// Sets to add to (negative: remove from) each planned exercise.
        var setAdjustment: Int {
            switch self {
            case .push, .normal: 0
            case .easy: -1
            case .recover: -2
            }
        }
    }

    var score: Int
    var factors: [Factor]
    var deloadSuggested = false

    var level: Level {
        switch score {
        case 85...: .push
        case 65..<85: .normal
        case 45..<65: .easy
        default: .recover
        }
    }
}

// MARK: - Weekly volume per muscle

struct MuscleVolume: Identifiable {
    enum Group: String, CaseIterable {
        case chest = "Chest", back = "Back", shoulders = "Shoulders", quads = "Quads",
             hamstrings = "Hamstrings", glutes = "Glutes", biceps = "Biceps", triceps = "Triceps",
             calves = "Calves", abs = "Abs"

        static func from(_ muscle: String) -> Group? {
            switch muscle.lowercased() {
            case "chest", "upper chest": .chest
            case "lats", "mid back", "upper back", "traps": .back
            case "front delts", "side delts", "rear delts", "shoulders": .shoulders
            case "quads": .quads
            case "hamstrings": .hamstrings
            case "glutes": .glutes
            case "biceps", "brachialis": .biceps
            case "triceps": .triceps
            case "calves": .calves
            case "abs", "core", "obliques": .abs
            default: nil
            }
        }
    }

    /// Rough weekly hard-set landmarks for most lifters. Individual needs vary a lot.
    static let maintenance = 4.0
    static let productiveLow = 8.0
    static let productiveHigh = 16.0
    static let high = 20.0

    let group: Group
    /// Hard sets in the last 7 days (primary muscle = 1 set, secondary = 0.5).
    let sets: Double
    var id: String { group.rawValue }

    var status: String {
        switch sets {
        case ..<Self.maintenance: "Below maintenance"
        case ..<Self.productiveLow: "Maintenance"
        case ...Self.productiveHigh: "Productive"
        case ...Self.high: "High"
        default: "Very high, watch recovery"
        }
    }
}

// MARK: - Training load

struct TrainingLoad {
    /// Volume (kg × reps) in the last 7 days.
    let acuteKg: Double
    /// Average weekly volume over the 4 weeks before that.
    let chronicWeeklyKg: Double
    /// Consecutive weeks (including this one) hitting the weekly session target.
    let hardWeeksInARow: Int

    /// Acute:chronic ratio. Around 0.8–1.3 is steady; big spikes raise fatigue and injury risk.
    var ratio: Double? { chronicWeeklyKg > 0 ? acuteKg / chronicWeeklyKg : nil }
}

// MARK: - Nutrition

struct NutritionTargets {
    var bodyWeightKg: Double?
    var proteinLowG: Double?
    var proteinHighG: Double?
    var maintenanceKcal: Double?
    /// True when maintenance came from your own intake + weight trend (not a formula).
    var maintenanceMeasured = false
    var targetKcal: Double?
    /// Actual weight change per week, as a percent of body weight (from the trend).
    var weeklyChangePercent: Double?
    var advice: String?
}

// MARK: - Engine

@MainActor
@Observable
final class CoachStore {
    static let shared = CoachStore()
    var report: CoachReport = .empty

    func refresh(context: ModelContext) async {
        report = await CoachEngine.makeReport(context: context)
    }
}

@MainActor
enum CoachEngine {
    static func makeReport(context: ModelContext, now: Date = .now) async -> CoachReport {
        let health = HealthKitManager.shared
        let cal = Calendar.current
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []).filter(\.isFinished)
        let weights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let plans = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        let kinds = Dictionary(plans.map { ($0.day, $0.kind) }, uniquingKeysWith: { a, _ in a })

        let load = trainingLoad(sessions: sessions, now: now)
        let volume = weeklyVolume(sessions: sessions, now: now)

        // Health inputs
        let rhr = await health.dailyAverages(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 30)
        let intake = await health.dailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 28)

        var factors: [Readiness.Factor] = []

        // Sleep
        if let sleep = health.today.sleepHoursLastNight {
            switch sleep {
            case ..<5: factors.append(.init(text: String(format: "Short sleep (%.1f h)", sleep), impact: -25))
            case ..<6: factors.append(.init(text: String(format: "Under 6 h sleep (%.1f h)", sleep), impact: -15))
            case ..<7: factors.append(.init(text: String(format: "A bit short on sleep (%.1f h)", sleep), impact: -5))
            case 7.5...: factors.append(.init(text: String(format: "Good sleep (%.1f h)", sleep), impact: 5))
            default: break
            }
        }

        // Resting heart rate vs 30-day baseline
        if rhr.count >= 7, let latest = rhr.last?.1 {
            let baseline = rhr.dropLast().map(\.1).reduce(0, +) / Double(rhr.count - 1)
            let diff = latest - baseline
            if diff >= 5 {
                factors.append(.init(text: "Resting HR \(Int(diff)) bpm above your normal", impact: -15))
            } else if diff >= 3 {
                factors.append(.init(text: "Resting HR a little high (+\(Int(diff)) bpm)", impact: -7))
            } else if diff <= -2 {
                factors.append(.init(text: "Resting HR at or below normal", impact: 3))
            }
        }

        // Shifts
        let today = cal.startOfDay(for: now)
        if let yesterday = cal.date(byAdding: .day, value: -1, to: today) {
            switch kinds[yesterday] {
            case .shift24: factors.append(.init(text: "Coming off a 24h shift", impact: -20))
            case .shift12: factors.append(.init(text: "Worked a 12h shift yesterday", impact: -8))
            default: break
            }
        }
        if kinds[today] == .shift24 { factors.append(.init(text: "24h shift today", impact: -15)) }

        // How the user said they feel in check-ins (last 24 h)
        let since = now.addingTimeInterval(-24 * 3600)
        let recentUser = ((try? context.fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.date > since }))) ?? [])
            .filter { $0.role == .user }
            .map { $0.text.lowercased() }
        let soreWords = ["sore", "slept badly", "tired", "exhausted", "beat up", "drained"]
        let negatives = recentUser.filter { text in soreWords.contains { text.contains($0) } }.count
        if negatives > 0 {
            factors.append(.init(text: "You reported feeling sore or tired", impact: -8 * min(negatives, 2)))
        }

        // Training load spike
        if let ratio = load.ratio {
            if ratio > 1.5 {
                factors.append(.init(text: String(format: "Training load jumped (%.1f× your usual week)", ratio), impact: -15))
            } else if ratio > 1.3 {
                factors.append(.init(text: String(format: "Training load up (%.1f× usual)", ratio), impact: -7))
            } else if ratio < 0.7 {
                factors.append(.init(text: "Lighter week than usual: room to push", impact: 5))
            }
        }

        // Performance trend: are lifts dropping?
        let trend = performanceTrend(sessions: sessions)
        if trend.dropping >= 2 {
            factors.append(.init(text: "\(trend.dropping) lifts below your recent level", impact: -15))
        } else if trend.improving >= 2 {
            factors.append(.init(text: "Lifts trending up", impact: 5))
        }

        // Days since last session
        if let last = sessions.last {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: last.startedAt), to: today).day ?? 0
            if days == 0 { factors.append(.init(text: "Already trained today", impact: -10)) }
            if days >= 3 { factors.append(.init(text: "\(days) days since your last session", impact: 5)) }
        }

        var readiness = Readiness(score: max(0, min(100, 75 + factors.map(\.impact).reduce(0, +))), factors: factors)
        if load.hardWeeksInARow >= 6 || (trend.dropping >= 2 && load.hardWeeksInARow >= 4) {
            readiness.deloadSuggested = true
        }

        let nutrition = nutritionTargets(weights: weights, intake: intake, now: now)
        return CoachReport(readiness: readiness, volume: volume, load: load, nutrition: nutrition, generatedAt: now)
    }

    // MARK: Pieces

    static func trainingLoad(sessions: [WorkoutSession], now: Date) -> TrainingLoad {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let fiveWeeksAgo = now.addingTimeInterval(-35 * 86_400)
        let acute = sessions.filter { $0.startedAt > weekAgo }.map(\.totalVolumeKg).reduce(0, +)
        let prior = sessions.filter { $0.startedAt <= weekAgo && $0.startedAt > fiveWeeksAgo }
        let chronic = prior.map(\.totalVolumeKg).reduce(0, +) / 4

        // Consecutive calendar weeks meeting the session target, counting back from this week.
        let cal = Calendar.current
        let target = AppSettings.sessionsPerWeek
        var streak = 0
        var weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        for i in 0..<16 {
            let end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let count = sessions.filter { $0.startedAt >= weekStart && $0.startedAt < end }.count
            if count >= target {
                streak += 1
            } else if i > 0 {
                break // the current week may still be in progress
            }
            weekStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        }
        return TrainingLoad(acuteKg: acute, chronicWeeklyKg: chronic, hardWeeksInARow: streak)
    }

    static func weeklyVolume(sessions: [WorkoutSession], now: Date) -> [MuscleVolume] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var totals: [MuscleVolume.Group: Double] = [:]
        for session in sessions where session.startedAt > weekAgo {
            for set in session.completedSets where set.reps > 0 {
                guard let ex = ExerciseCatalog.exercise(set.exerciseID) else { continue }
                let primary = Set(ex.primaryMuscles.compactMap(MuscleVolume.Group.from))
                let secondary = Set(ex.secondaryMuscles.compactMap(MuscleVolume.Group.from)).subtracting(primary)
                for g in primary { totals[g, default: 0] += 1 }
                for g in secondary { totals[g, default: 0] += 0.5 }
            }
        }
        return MuscleVolume.Group.allCases.map { MuscleVolume(group: $0, sets: totals[$0] ?? 0) }
    }

    /// Compares each lift's best estimated 1RM in the latest session with its median over the
    /// three sessions before. More than 5% down counts as dropping, more than 2% up as improving.
    static func performanceTrend(sessions: [WorkoutSession]) -> (dropping: Int, improving: Int) {
        guard let last = sessions.last else { return (0, 0) }
        var dropping = 0, improving = 0
        for exID in Set(last.completedSets.map(\.exerciseID)) {
            let latest = last.sets(for: exID).filter { !$0.skipped }.map(\.estimatedOneRepMaxKg).max() ?? 0
            guard latest > 0 else { continue }
            let previous = sessions.dropLast().reversed()
                .compactMap { s -> Double? in s.sets(for: exID).filter { !$0.skipped }.map(\.estimatedOneRepMaxKg).max() }
                .filter { $0 > 0 }
                .prefix(3)
            guard previous.count >= 2 else { continue }
            let sorted = previous.sorted()
            let median = sorted[sorted.count / 2]
            if latest < median * 0.95 { dropping += 1 } else if latest > median * 1.02 { improving += 1 }
        }
        return (dropping, improving)
    }

    static func nutritionTargets(weights: [BodyWeightEntry], intake: [(Date, Double)], now: Date) -> NutritionTargets {
        var n = NutritionTargets()
        let recent = weights.filter { $0.date > now.addingTimeInterval(-7 * 86_400) }
        let bw = recent.isEmpty ? weights.last?.weightKg : recent.map(\.weightKg).reduce(0, +) / Double(recent.count)
        guard let bw, bw > 0 else {
            n.advice = "Log your body weight (or connect a scale through Apple Health) to get protein and calorie targets."
            return n
        }
        n.bodyWeightKg = bw
        n.proteinLowG = bw * 1.6
        n.proteinHighG = bw * 2.2

        // Weight trend over the last 28 days (least squares slope, kg per day).
        let window = weights.filter { $0.date > now.addingTimeInterval(-28 * 86_400) }
        var slopePerDay: Double?
        if window.count >= 4, let first = window.first?.date, let lastDate = window.last?.date,
           lastDate.timeIntervalSince(first) >= 10 * 86_400 {
            let xs = window.map { $0.date.timeIntervalSince(first) / 86_400 }
            let ys = window.map(\.weightKg)
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
            let den = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
            if den > 0 { slopePerDay = num / den }
        }
        if let slope = slopePerDay { n.weeklyChangePercent = slope * 7 / bw * 100 }

        // Maintenance: measured from logged food + weight change when there's enough of both,
        // otherwise a rough body-weight estimate for an active person.
        let loggedDays = intake.filter { $0.1 > 800 } // ignore days that were barely logged
        if loggedDays.count >= 10, let slope = slopePerDay {
            let avgIntake = loggedDays.map(\.1).reduce(0, +) / Double(loggedDays.count)
            n.maintenanceKcal = avgIntake - slope * 7700
            n.maintenanceMeasured = true
        } else {
            n.maintenanceKcal = bw * 33
        }

        let goal = AppSettings.goal
        let ratePerWeekKg = goal.direction * AppSettings.goalRatePercent / 100 * bw
        if let m = n.maintenanceKcal {
            n.targetKcal = m + ratePerWeekKg * 7700 / 7
        }

        // Is the actual trend matching the goal?
        if let actual = n.weeklyChangePercent {
            let target = goal.direction * AppSettings.goalRatePercent
            let gap = actual - target
            switch goal {
            case .buildMuscle:
                if gap > 0.25 { n.advice = String(format: "Gaining %.2f%%/week, faster than your %.2f%% target. Trim about 150–200 kcal a day to keep it lean.", actual, target) }
                else if gap < -0.2 { n.advice = String(format: "Weight is flat or dropping (%.2f%%/week). Add about 150–250 kcal a day to support muscle gain.", actual) }
                else { n.advice = "Weight gain is on target. Keep it up." }
            case .loseFat:
                if actual > -0.1 { n.advice = "Weight isn't dropping yet. Take about 200–300 kcal a day off and keep protein high." }
                else if actual < -1.0 { n.advice = String(format: "Losing %.2f%%/week, faster than ideal for keeping muscle. Add about 150–200 kcal a day.", -actual) }
                else { n.advice = "Fat loss is on a muscle-friendly pace. Keep lifting heavy." }
            case .recomp, .maintain:
                if abs(actual) > 0.3 { n.advice = String(format: "Weight is moving %.2f%%/week. Adjust calories about 150 kcal toward maintenance.", actual) }
                else { n.advice = "Weight is stable. Keep protein high and keep adding reps." }
            }
        }
        return n
    }
}
