import Foundation

enum WeightUnit: String, CaseIterable, Identifiable, Codable {
    case lbs, kg

    var id: String { rawValue }
    var label: String { rawValue }

    static let kgPerLb = 0.45359237

    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg / WeightUnit.kgPerLb }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value * WeightUnit.kgPerLb }

    /// "135 lbs", "61.2 kg". Whole numbers drop the decimal.
    func format(kg: Double, withUnit: Bool = true) -> String {
        let v = fromKg(kg)
        let s = WeightUnit.number(v)
        return withUnit ? "\(s) \(rawValue)" : s
    }

    static func number(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// Default +/- step on the logging pad when the exercise has no specific increment.
    var defaultStep: Double { self == .kg ? 2.5 : 5 }
}

/// Keys for values kept in UserDefaults / @AppStorage.
enum SettingsKey {
    static let unit = "unit"
    static let model = "claudeModel"
    static let restSeconds = "restSeconds"
    static let checkInSchedule = "checkInSchedule"
    static let trainingWeekdays = "trainingWeekdays"
    static let sessionsPerWeek = "sessionsPerWeek"
    static let healthIncludeInChat = "healthIncludeInChat"
    static let hasOnboarded = "hasOnboarded"
    static let appearance = "appearance"
    static let goal = "goal"
    static let goalRatePercent = "goalRatePercent"
    static let leaderboardEnabled = "leaderboardEnabled"
    static let userName = "userName"
    static let userContext = "userContext"
}

enum AppSettings {
    static var defaults: UserDefaults { .standard }

    static var unit: WeightUnit {
        WeightUnit(rawValue: defaults.string(forKey: SettingsKey.unit) ?? "") ?? .lbs
    }

    static var model: String {
        defaults.string(forKey: SettingsKey.model) ?? ClaudeModel.defaultID
    }

    static var restSeconds: Int {
        let v = defaults.integer(forKey: SettingsKey.restSeconds)
        return v > 0 ? v : 90
    }

    static var sessionsPerWeek: Int {
        let v = defaults.integer(forKey: SettingsKey.sessionsPerWeek)
        return v > 0 ? v : 2
    }

    /// Preferred training weekdays (Calendar weekday numbers, 1 = Sunday). Default: Tuesday and Friday.
    static var preferredWeekdays: Set<Int> {
        get {
            guard let s = defaults.string(forKey: SettingsKey.trainingWeekdays), !s.isEmpty else { return [3, 6] }
            return Set(s.split(separator: ",").compactMap { Int($0) })
        }
        set {
            defaults.set(newValue.sorted().map(String.init).joined(separator: ","), forKey: SettingsKey.trainingWeekdays)
        }
    }

    static var goal: TrainingGoal {
        TrainingGoal(rawValue: defaults.string(forKey: SettingsKey.goal) ?? "") ?? .buildMuscle
    }

    /// Target body-weight change per week as a percent of body weight (e.g. 0.25 for a lean gain).
    static var goalRatePercent: Double {
        let v = defaults.double(forKey: SettingsKey.goalRatePercent)
        return v > 0 ? v : goal.defaultRatePercent
    }

    static var includeHealthInChat: Bool {
        defaults.object(forKey: SettingsKey.healthIncludeInChat) as? Bool ?? true
    }
}

/// Models offered in Settings. The user can also type any model id.
struct ClaudeModel: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String

    static let defaultID = "claude-sonnet-5-5"

    static let options: [ClaudeModel] = [
        ClaudeModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", note: "Default. Fast and smart, good value."),
        ClaudeModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", note: "More thorough answers, costs about twice as much."),
        ClaudeModel(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", note: "Cheapest and quickest, shorter answers."),
        ClaudeModel(id: "claude-fable-5-2", name: "Claude Fable 5.2", note: "Most capable, most expensive."),
    ]
}

/// What the user is training for. Drives calorie and protein targets and how hard the coach pushes.
enum TrainingGoal: String, CaseIterable, Identifiable {
    case buildMuscle, loseFat, recomp, maintain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .buildMuscle: "Build muscle"
        case .loseFat: "Lose fat"
        case .recomp: "Recomp (lose fat, keep building)"
        case .maintain: "Maintain and get healthier"
        }
    }

    /// Sign of the weekly weight change.
    var direction: Double {
        switch self {
        case .buildMuscle: 1
        case .loseFat: -1
        case .recomp, .maintain: 0
        }
    }

    var defaultRatePercent: Double {
        switch self {
        case .buildMuscle: 0.25
        case .loseFat: 0.5
        case .recomp, .maintain: 0
        }
    }
}
