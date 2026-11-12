import Foundation
import HealthKit
import Observation

/// Reads and writes Apple Health. Every permission group is requested separately with a plain
/// explanation, and every read returns nil/empty when access is missing so the app keeps working.
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Groups that the user has been asked about (HealthKit never reveals if *read* access was granted).
    private(set) var askedGroups: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "healthAskedGroups") ?? [])

    var today = TodayHealth()

    enum DataGroup: String, CaseIterable, Identifiable {
        case activity, sleep, heart, body, nutrition, workouts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .activity: "Steps and active energy"
            case .sleep: "Sleep"
            case .heart: "Heart rate"
            case .body: "Body weight"
            case .nutrition: "Food (calories and macros)"
            case .workouts: "Workouts"
            }
        }

        var symbol: String {
            switch self {
            case .activity: "figure.walk"
            case .sleep: "bed.double"
            case .heart: "heart"
            case .body: "scalemass"
            case .nutrition: "fork.knife"
            case .workouts: "dumbbell"
            }
        }

        var why: String {
            switch self {
            case .activity: "Shows today's steps on the Today screen and tells the trainer how active you've been."
            case .sleep: "Morning check-ins look at last night's sleep to adjust today's plan."
            case .heart: "Gives the trainer your resting heart rate trend as a recovery signal."
            case .body: "Imports weigh-ins from your scale and saves the ones you log here back to Health."
            case .nutrition: "Reads calories and protein/carbs/fat that FatSecret or other food apps save to Health. Nothing is written."
            case .workouts: "Saves every finished session to Health as a strength workout, and reads other workouts you do."
            }
        }

        var readTypes: Set<HKObjectType> {
            switch self {
            case .activity:
                [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
            case .sleep:
                [HKCategoryType(.sleepAnalysis)]
            case .heart:
                [HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate)]
            case .body:
                [HKQuantityType(.bodyMass)]
            case .nutrition:
                [HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
                 HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal)]
            case .workouts:
                [HKObjectType.workoutType()]
            }
        }

        var writeTypes: Set<HKSampleType> {
            switch self {
            case .body: [HKQuantityType(.bodyMass)]
            case .workouts: [HKObjectType.workoutType()]
            default: []
            }
        }
    }

    func hasAsked(_ group: DataGroup) -> Bool { askedGroups.contains(group.rawValue) }

    func request(_ group: DataGroup) async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: group.writeTypes, read: group.readTypes)
            askedGroups.insert(group.rawValue)
            UserDefaults.standard.set(Array(askedGroups), forKey: "healthAskedGroups")
            await refreshToday()
        } catch {
            // The user can always retry from Settings.
        }
    }

    func canWrite(_ type: HKSampleType) -> Bool {
        isAvailable && store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: - Reads

    struct TodayHealth {
        var steps: Double?
        var activeEnergyKcal: Double?
        var dietaryKcal: Double?
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?
        var sleepHoursLastNight: Double?
        var restingHeartRate: Double?
        var latestBodyMassKg: Double?
        var refreshedAt: Date?
    }

    func refreshToday() async {
        guard isAvailable else { return }
        let start = Calendar.current.startOfDay(for: .now)
        async let steps = sum(.stepCount, unit: .count(), from: start)
        async let active = sum(.activeEnergyBurned, unit: .kilocalorie(), from: start)
        async let kcal = sum(.dietaryEnergyConsumed, unit: .kilocalorie(), from: start)
        async let protein = sum(.dietaryProtein, unit: .gram(), from: start)
        async let carbs = sum(.dietaryCarbohydrates, unit: .gram(), from: start)
        async let fat = sum(.dietaryFatTotal, unit: .gram(), from: start)
        async let sleep = sleepHoursLastNight()
        async let rhr = latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let mass = latest(.bodyMass, unit: .gramUnit(with: .kilo))

        var t = TodayHealth()
        t.steps = await steps
        t.activeEnergyKcal = await active
        t.dietaryKcal = await kcal
        t.proteinG = await protein
        t.carbsG = await carbs
        t.fatG = await fat
        t.sleepHoursLastNight = await sleep
        t.restingHeartRate = await rhr
        t.latestBodyMassKg = await mass
        t.refreshedAt = .now
        today = t
    }

    /// Daily totals for the last `days` days (oldest first). Used for trainer context.
    func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [(Date, Double)] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86_400)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var out: [(Date, Double)] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let q = stats.sumQuantity() { out.append((stats.startDate, q.doubleValue(for: unit))) }
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Body-mass samples since a date, for importing into the weight log.
    func bodyMassSamples(since: Date) async -> [(uuid: String, date: Date, kg: Double)] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, _ in
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        let ownBundle = Bundle.main.bundleIdentifier
        return samples
            .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle } // our own writes are already in the log
            .map { ($0.uuid.uuidString, $0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, _ in
                let value = (results?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(q)
        }
    }

    /// Hours asleep between 6 pm yesterday and noon today (covers night shifts poorly by design:
    /// the trainer is told it's "last night" and the user can correct it in chat).
    private func sleepHoursLastNight() async -> Double? {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let start = todayStart.addingTimeInterval(-6 * 3600)
        let end = todayStart.addingTimeInterval(12 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        guard !asleep.isEmpty else { return nil }
        // Merge overlapping intervals (watch + phone can both report).
        let intervals = asleep.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current = intervals[0]
        for next in intervals.dropFirst() {
            if next.0 <= current.1 {
                current.1 = max(current.1, next.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = next
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total / 3600
    }

    // MARK: - Writes

    func saveBodyMass(kg: Double, date: Date) async {
        let type = HKQuantityType(.bodyMass)
        guard canWrite(type) else { return }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: date, end: date)
        try? await store.save(sample)
    }

    /// Saves a finished session as a traditional strength training workout. Returns true on success.
    func saveWorkout(start: Date, end: Date, title: String, totalVolumeKg: Double) async -> Bool {
        guard canWrite(HKObjectType.workoutType()) else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                HKMetadataKeyWorkoutBrandName: "MP Coaching",
                "MPCoachingSessionTitle": title,
                "MPCoachingTotalVolumeKg": totalVolumeKg,
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }
}
