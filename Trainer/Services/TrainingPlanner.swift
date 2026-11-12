import Foundation

/// Places this week's sessions around shifts, clinicals and classes instead of fixed weekdays.
///
/// Rules: hit the weekly target (default 2), never on a 12h/24h shift day, avoid the day after a
/// 24h shift, keep at least one rest day between sessions when possible, prefer free days and the
/// user's preferred weekdays, and alternate Day 1 / Day 2.
enum TrainingPlanner {
    struct DayPlanResult: Identifiable {
        let day: Date
        let kind: DayKind
        let trained: Bool
        let planned: WorkoutTemplate?

        var id: Date { day }
        var isToday: Bool { Calendar.current.isDateInToday(day) }
    }

    static func week(containing date: Date = .now) -> [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    static func plan(
        days: [Date],
        dayKinds: [Date: DayKind],
        finishedSessions: [WorkoutSession],
        program: Program = DefaultProgram.current,
        preferredWeekdays: Set<Int> = AppSettings.preferredWeekdays,
        sessionsPerWeek: Int = AppSettings.sessionsPerWeek,
        now: Date = .now
    ) -> [DayPlanResult] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let trainedDays = Set(finishedSessions.map { cal.startOfDay(for: $0.startedAt) })
        let doneThisWeek = days.filter { trainedDays.contains($0) }.count
        var remaining = max(0, sessionsPerWeek - doneThisWeek)

        func kind(_ d: Date) -> DayKind { dayKinds[d] ?? .free }
        func score(_ d: Date) -> Int {
            let k = kind(d)
            guard k.trainingScore > 0 else { return 0 }
            var s = k.trainingScore * 10
            if preferredWeekdays.contains(cal.component(.weekday, from: d)) { s += 5 }
            if let yesterday = cal.date(byAdding: .day, value: -1, to: d), kind(yesterday) == .shift24 { s -= 25 }
            if cal.isDate(d, inSameDayAs: today) { s += 1 } // tie-break: sooner is better
            return max(s, 0)
        }

        // Include recent sessions just before the week so Monday isn't planned right after Sunday's workout.
        var occupied = trainedDays
        let candidates = days
            .filter { $0 >= today && !trainedDays.contains($0) && score($0) > 0 }
            .sorted { score($0) != score($1) ? score($0) > score($1) : $0 < $1 }

        var picked: [Date] = []
        for minGap in [2, 1] where remaining > 0 {
            for d in candidates where remaining > 0 && !picked.contains(d) {
                let ok = occupied.allSatisfy { abs(cal.dateComponents([.day], from: $0, to: d).day ?? 99) >= minGap }
                if ok {
                    picked.append(d)
                    occupied.insert(d)
                    remaining -= 1
                }
            }
        }

        // Assign templates in date order, continuing the alternation from the last finished session.
        let lastTemplateID = finishedSessions.filter { $0.templateID != nil }.max { $0.startedAt < $1.startedAt }?.templateID
        var nextTemplate = program.template(after: lastTemplateID)
        var assignment: [Date: WorkoutTemplate] = [:]
        for d in picked.sorted() {
            assignment[d] = nextTemplate
            nextTemplate = program.template(after: nextTemplate.id)
        }

        return days.map { d in
            DayPlanResult(day: d, kind: kind(d), trained: trainedDays.contains(d), planned: assignment[d])
        }
    }

    /// The template to suggest when the user taps "Start workout" right now.
    static func suggestedTemplate(finishedSessions: [WorkoutSession], program: Program = DefaultProgram.current) -> WorkoutTemplate {
        let last = finishedSessions.filter { $0.templateID != nil }.max { $0.startedAt < $1.startedAt }?.templateID
        return program.template(after: last)
    }
}
