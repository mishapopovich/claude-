import Foundation
import SwiftData
import HealthKit

/// Builds the trainer's system prompt: a fixed persona (cached by the API) plus a fresh snapshot
/// of the user's training and health data. Only summary numbers are included, and only when the
/// user has added their own API key.
@MainActor
enum TrainerContext {
    static let persona = """
    You are the user's personal strength coach inside MP Coaching. You are a science-based \
    lifting and nutrition coach: direct, practical, a bit of dry humor, built on progressive \
    overload, weekly volume landmarks, fatigue management and deloads, high protein, and \
    consistency over perfection. You have your own voice; never claim to be or imitate any real \
    person.

    How you coach:
    - Use the data snapshot below. Refer to actual numbers (weights, reps, dates, sleep, steps, food) \
    when they help. Be honest about what the data does and does not show; if something is missing, \
    say so instead of guessing.
    - Keep answers short and usable between sets or on a break: a few sentences or a tight list. Go \
    longer only when asked.
    - Encouraging, never preachy or guilt-tripping. Missed sessions happen; give the next best step.
    - Many users have irregular schedules (classes, clinicals, 12h and 24h shifts). Use the week \
    plan in the snapshot and adapt around it: shorter sessions after shifts, move training days, \
    and treat sleep debt as a real recovery factor.
    - Default program: two ~30 minute full-body sessions per week. Progression: add reps, or add \
    2.5–5 lb, or cut rest by 10–15 seconds each week. Start light, form first.
    - Use the user's preferred units (given in the snapshot).

    Safety boundaries:
    - You are not a medical provider. Do not diagnose conditions, interpret symptoms, or give \
    medical advice, medication advice, or injury treatment plans. Give training and general \
    nutrition information only.
    - If the user mentions pain that is sharp, worsening, or lasting, chest pain, fainting, numbness, \
    or anything that sounds medical, say plainly that it is worth raising with a clinician, and keep \
    training advice conservative.
    - No extreme diets, dehydration, or drug advice.

    Fatigue and pushing: the snapshot includes a readiness score and the factors behind it. When \
    readiness is low or a deload is suggested, protect recovery (fewer sets, leave reps in reserve, \
    lighter week). When readiness is high, push: aim for rep or weight PRs, and mention where the \
    user stands against friends on their leaderboard if that data is present. Explain the why in \
    one line.

    Check-ins: when a message says it is a scheduled check-in, write a short, friendly check-in \
    (2–4 sentences) that fits the time of day — morning: sleep and today's plan; midday: food and \
    movement so far; evening: a wrap-up and tomorrow — and end with one simple question.
    """

    static func snapshot(context: ModelContext, health: HealthKitManager.TodayHealth, includeHealth: Bool) async -> String {
        let unit = AppSettings.unit
        let now = Date.now
        var lines: [String] = []

        lines.append("DATA SNAPSHOT (generated \(now.formatted(date: .complete, time: .shortened)))")
        lines.append("Units: \(unit.rawValue)")
        let name = UserDefaults.standard.string(forKey: SettingsKey.userName) ?? ""
        if !name.isEmpty { lines.append("User's name: \(name)") }
        let about = UserDefaults.standard.string(forKey: SettingsKey.userContext) ?? ""
        if !about.isEmpty { lines.append("About the user (their own words): \(about)") }

        // Week plan
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        let finished = sessions.filter(\.isFinished)
        let plans = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        let kinds = Dictionary(plans.map { ($0.day, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let week = TrainingPlanner.plan(days: TrainingPlanner.week(), dayKinds: kinds, finishedSessions: finished)
        lines.append("")
        lines.append("THIS WEEK (target \(AppSettings.sessionsPerWeek) sessions):")
        for d in week {
            var s = "- \(d.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(d.kind.label)"
            if d.trained { s += " — trained" } else if let t = d.planned { s += " — planned \(t.name) (\(t.focus))" }
            if d.isToday { s += "  ← today" }
            lines.append(s)
        }

        // Recent sessions
        lines.append("")
        lines.append("RECENT SESSIONS (last 21 days):")
        let recent = finished.filter { $0.startedAt > now.addingTimeInterval(-21 * 86_400) }.prefix(8)
        if recent.isEmpty { lines.append("- none logged") }
        for session in recent {
            let mins = Int(session.duration / 60)
            lines.append("- \(session.startedAt.formatted(date: .abbreviated, time: .omitted)) \(session.templateName), \(mins) min, volume \(unit.format(kg: session.totalVolumeKg))")
            for exID in session.exerciseOrder {
                let sets = session.sets(for: exID).filter { !$0.skipped }
                guard !sets.isEmpty else { continue }
                let setText = sets.map { "\(unit.format(kg: $0.weightKg, withUnit: false))×\($0.reps)" }.joined(separator: ", ")
                lines.append("    \(ExerciseCatalog.name(exID)): \(setText)")
            }
        }
        if let active = sessions.first(where: { !$0.isFinished }) {
            lines.append("- In progress now: \(active.templateName), \(active.completedSets.count) sets logged")
        }

        // Big three
        lines.append("")
        lines.append("BIG THREE MAXES:")
        var total = 0.0
        for lift in BigThree.allCases {
            if let m = PRService.currentMax(for: lift, in: context) {
                total += m.valueKg
                let how = m.kind == .tested1RM ? "tested" : "estimated from \(unit.format(kg: m.weightKg))×\(m.reps)"
                lines.append("- \(lift.name): \(unit.format(kg: m.valueKg)) (\(how), \(m.date.formatted(date: .abbreviated, time: .omitted)))")
            } else {
                lines.append("- \(lift.name): no data")
            }
        }
        if total > 0 { lines.append("- Total: \(unit.format(kg: total))") }

        // Body weight
        let weights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        lines.append("")
        lines.append("BODY WEIGHT:")
        if let latest = weights.first {
            lines.append("- Latest: \(unit.format(kg: latest.weightKg)) on \(latest.date.formatted(date: .abbreviated, time: .omitted))")
            let last7 = weights.filter { $0.date > now.addingTimeInterval(-7 * 86_400) }
            let prev7 = weights.filter { $0.date <= now.addingTimeInterval(-7 * 86_400) && $0.date > now.addingTimeInterval(-14 * 86_400) }
            if !last7.isEmpty { lines.append("- 7-day average: \(unit.format(kg: last7.map(\.weightKg).reduce(0, +) / Double(last7.count))) (\(last7.count) weigh-ins)") }
            if !prev7.isEmpty { lines.append("- Previous 7-day average: \(unit.format(kg: prev7.map(\.weightKg).reduce(0, +) / Double(prev7.count)))") }
        } else {
            lines.append("- none logged")
        }

        // Coach engine (same numbers the app shows)
        let report = CoachStore.shared.report
        lines.append("")
        lines.append("READINESS (app's rules-based score, 0–100): \(report.readiness.score) — \(report.readiness.level.title)")
        for f in report.readiness.factors { lines.append("- \(f.text) (\(f.impact >= 0 ? "+" : "")\(f.impact))") }
        if report.readiness.deloadSuggested { lines.append("- Deload suggested (many hard weeks in a row or lifts dropping)") }
        lines.append("Training load: last 7 days \(unit.format(kg: report.load.acuteKg)), usual week \(unit.format(kg: report.load.chronicWeeklyKg)), hard weeks in a row \(report.load.hardWeeksInARow)")
        let vol = report.volume.filter { $0.sets > 0 }.map { "\($0.group.rawValue) \(String(format: "%.1f", $0.sets))" }
        lines.append("Weekly hard sets per muscle: " + (vol.isEmpty ? "none this week" : vol.joined(separator: ", ")))
        lines.append("Goal: \(AppSettings.goal.label), target \(String(format: "%.2f", AppSettings.goal.direction * AppSettings.goalRatePercent))% body weight per week")
        let n = report.nutrition
        if let low = n.proteinLowG, let high = n.proteinHighG { lines.append("Protein target: \(Int(low))–\(Int(high)) g/day") }
        if let m = n.maintenanceKcal { lines.append("Maintenance: \(Int(m)) kcal (\(n.maintenanceMeasured ? "measured from intake + weight trend" : "rough estimate"))") }
        if let t = n.targetKcal { lines.append("Calorie target: \(Int(t)) kcal/day") }
        if let w = n.weeklyChangePercent { lines.append("Weight trend: \(String(format: "%+.2f", w))% per week") }

        // Health
        lines.append("")
        if includeHealth {
            lines.append("APPLE HEALTH (today so far unless noted; missing = no data or no permission):")
            func add(_ label: String, _ v: Double?, _ fmt: (Double) -> String) {
                lines.append("- \(label): \(v.map(fmt) ?? "no data")")
            }
            add("Sleep last night", health.sleepHoursLastNight) { String(format: "%.1f h", $0) }
            add("Steps", health.steps) { "\(Int($0))" }
            add("Active energy", health.activeEnergyKcal) { "\(Int($0)) kcal" }
            add("Food logged", health.dietaryKcal) { "\(Int($0)) kcal" }
            add("Protein", health.proteinG) { "\(Int($0)) g" }
            add("Carbs", health.carbsG) { "\(Int($0)) g" }
            add("Fat", health.fatG) { "\(Int($0)) g" }
            add("Resting heart rate (latest)", health.restingHeartRate) { "\(Int($0)) bpm" }

            let steps = await HealthKitManager.shared.dailySums(.stepCount, unit: .count(), days: 7)
            if !steps.isEmpty {
                let avg = steps.map(\.1).reduce(0, +) / Double(steps.count)
                lines.append("- Steps, 7-day average: \(Int(avg))")
            }
            let kcal = await HealthKitManager.shared.dailySums(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 7)
            if !kcal.isEmpty {
                let days = kcal.map { "\($0.0.formatted(.dateTime.weekday(.abbreviated))) \(Int($0.1))" }.joined(separator: ", ")
                lines.append("- Food kcal by day (last 7): \(days)")
            }
        } else {
            lines.append("APPLE HEALTH: the user chose not to share Health data with the trainer.")
        }

        return lines.joined(separator: "\n")
    }
}
