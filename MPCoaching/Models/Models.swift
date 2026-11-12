import Foundation
import SwiftData

// MARK: - Workout logging

/// One gym session. Created when the user taps "Start", finished when they tap "Finish".
/// Sets are saved the moment they are logged, so a crash or a phone call never loses data.
@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    /// ID of the `WorkoutTemplate` this session followed, or nil for a free session.
    var templateID: String?
    var templateName: String = "Free session"
    var notes: String = ""
    /// Exercise IDs in the order the user worked through them (planned + any added).
    var exerciseOrder: [String] = []
    var savedToHealth: Bool = false
    /// Sets added to / removed from each planned exercise because of readiness (0 = full plan).
    var setAdjustment: Int = 0
    /// Readiness score when the session started, for the history and the coach.
    var readinessAtStart: Int?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.session)
    var sets: [ExerciseSet] = []

    init(templateID: String?, templateName: String, exerciseOrder: [String], startedAt: Date = .now) {
        self.templateID = templateID
        self.templateName = templateName
        self.exerciseOrder = exerciseOrder
        self.startedAt = startedAt
    }

    var isFinished: Bool { endedAt != nil }
    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }

    var completedSets: [ExerciseSet] { sets.filter { !$0.skipped } }

    /// Total volume in kilograms (weight x reps summed over completed sets).
    var totalVolumeKg: Double { completedSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) } }

    func sets(for exerciseID: String) -> [ExerciseSet] {
        sets.filter { $0.exerciseID == exerciseID }.sorted { $0.setNumber < $1.setNumber }
    }
}

@Model
final class ExerciseSet {
    var id: UUID = UUID()
    var session: WorkoutSession?
    var exerciseID: String = ""
    var setNumber: Int = 1
    /// Always stored in kilograms. Converted to the user's unit for display.
    var weightKg: Double = 0
    var reps: Int = 0
    var completedAt: Date = Date()
    var skipped: Bool = false

    init(exerciseID: String, setNumber: Int, weightKg: Double, reps: Int, skipped: Bool = false, completedAt: Date = .now) {
        self.exerciseID = exerciseID
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.skipped = skipped
        self.completedAt = completedAt
    }

    /// Epley estimated one-rep max, in kilograms.
    var estimatedOneRepMaxKg: Double { OneRepMax.epley(weight: weightKg, reps: reps) }
}

// MARK: - Body weight and PRs

enum WeightSource: String, Codable {
    case manual
    case healthKit
}

@Model
final class BodyWeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0
    var sourceRaw: String = WeightSource.manual.rawValue
    /// HealthKit sample UUID, so imports are never duplicated.
    var healthKitUUID: String?

    init(date: Date, weightKg: Double, source: WeightSource, healthKitUUID: String? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.sourceRaw = source.rawValue
        self.healthKitUUID = healthKitUUID
    }

    var source: WeightSource { WeightSource(rawValue: sourceRaw) ?? .manual }
}

enum PRKind: String, Codable, CaseIterable {
    /// A one-rep max the user actually tested and typed in.
    case tested1RM
    /// Best Epley estimate from a logged set.
    case estimated1RM
    /// Heaviest weight moved for any number of reps.
    case heaviestWeight

    var label: String {
        switch self {
        case .tested1RM: "Tested 1RM"
        case .estimated1RM: "Estimated 1RM"
        case .heaviestWeight: "Heaviest weight"
        }
    }
}

@Model
final class PersonalRecord {
    var id: UUID = UUID()
    var exerciseID: String = ""
    var kindRaw: String = PRKind.estimated1RM.rawValue
    var weightKg: Double = 0
    var reps: Int = 1
    var date: Date = Date()
    var sessionID: UUID?
    /// The ExerciseSet that produced this record (nil for tested maxes).
    var setID: UUID?

    init(exerciseID: String, kind: PRKind, weightKg: Double, reps: Int, date: Date = .now, sessionID: UUID? = nil, setID: UUID? = nil) {
        self.exerciseID = exerciseID
        self.kindRaw = kind.rawValue
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
        self.sessionID = sessionID
        self.setID = setID
    }

    var kind: PRKind { PRKind(rawValue: kindRaw) ?? .estimated1RM }

    /// The number this record is ranked by: the 1RM value for 1RM kinds, the raw weight otherwise.
    var valueKg: Double {
        switch kind {
        case .tested1RM, .heaviestWeight: weightKg
        case .estimated1RM: OneRepMax.epley(weight: weightKg, reps: reps)
        }
    }
}

// MARK: - Chat

enum ChatRole: String, Codable {
    case user
    case assistant
}

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var roleRaw: String = ChatRole.user.rawValue
    var text: String = ""
    var date: Date = Date()
    var isCheckIn: Bool = false
    /// True if this message failed to send / generate (shown with a retry hint, excluded from API history).
    var failed: Bool = false

    init(role: ChatRole, text: String, isCheckIn: Bool = false, date: Date = .now) {
        self.roleRaw = role.rawValue
        self.text = text
        self.isCheckIn = isCheckIn
        self.date = date
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
}

// MARK: - Week planning (irregular schedule)

/// What the user has on a given day. Used to place training sessions and to mute check-ins.
enum DayKind: String, Codable, CaseIterable, Identifiable {
    case free
    case classes
    case clinical
    case shift12
    case shift24

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "Free"
        case .classes: "Classes"
        case .clinical: "Clinical"
        case .shift12: "12h shift"
        case .shift24: "24h shift"
        }
    }

    var symbol: String {
        switch self {
        case .free: "sun.max"
        case .classes: "book"
        case .clinical: "stethoscope"
        case .shift12: "cross.case"
        case .shift24: "moon.zzz"
        }
    }

    /// How good a day this is for a ~30 minute session. 0 = do not schedule.
    var trainingScore: Int {
        switch self {
        case .free: 3
        case .classes: 2
        case .clinical: 1
        case .shift12, .shift24: 0
        }
    }
}

@Model
final class DayPlan {
    /// Start of the day (local calendar).
    var day: Date = Date()
    var kindRaw: String = DayKind.free.rawValue

    init(day: Date, kind: DayKind) {
        self.day = Calendar.current.startOfDay(for: day)
        self.kindRaw = kind.rawValue
    }

    var kind: DayKind {
        get { DayKind(rawValue: kindRaw) ?? .free }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Helpers

enum OneRepMax {
    /// Epley formula: 1RM = w * (1 + reps / 30). A single rep is its own 1RM.
    static func epley(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        WorkoutSession.self,
        ExerciseSet.self,
        BodyWeightEntry.self,
        PersonalRecord.self,
        ChatMessage.self,
        DayPlan.self,
    ]
}
