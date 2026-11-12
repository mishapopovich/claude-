import Foundation
import CloudKit
import SwiftData
import Observation

/// One person on a leaderboard. Only lifts, totals and training consistency are shared —
/// never body weight or health data.
struct LifterEntry: Identifiable, Hashable {
    let id: String            // CloudKit record name
    var displayName: String
    var username: String
    var benchKg: Double
    var squatKg: Double
    var deadliftKg: Double
    var benchTested: Bool
    var squatTested: Bool
    var deadliftTested: Bool
    var sessionsThisWeek: Int
    var streakWeeks: Int
    var updatedAt: Date
    var isMe = false

    var totalKg: Double { benchKg + squatKg + deadliftKg }

    func value(_ board: LeaderboardKind) -> Double {
        switch board {
        case .total: totalKg
        case .bench: benchKg
        case .squat: squatKg
        case .deadlift: deadliftKg
        case .consistency: Double(streakWeeks * 10 + sessionsThisWeek)
        }
    }
}

enum LeaderboardKind: String, CaseIterable, Identifiable {
    case total = "Total", bench = "Bench", squat = "Squat", deadlift = "Deadlift", consistency = "Streak"
    var id: String { rawValue }
}

struct LeaderboardGroup: Identifiable, Codable, Hashable {
    let code: String
    var name: String
    var id: String { code }
}

/// Friends, groups and leaderboards on the CloudKit public database.
///
/// Record types (created automatically in the Development environment on first use):
/// - `Lifter`     id "lifter-<user>"           displayName, username, bench/squat/deadlift (kg), *Tested flags, sessionsThisWeek, streakWeeks, updatedAt
/// - `Username`   id "username-<name>"         owner (lifter record name). Claims a unique username.
/// - `LBGroup`    id "group-<CODE>"            name, code, owner
/// - `Membership` id "member-<CODE>-<user>"    groupCode (must be marked Queryable in CloudKit Console), lifter
@MainActor
@Observable
final class SocialStore {
    static let shared = SocialStore()

    enum Status: Equatable {
        case notConfigured      // AppConfig.cloudKitContainerID is nil
        case checking
        case noAccount          // not signed in to iCloud
        case needsProfile       // signed in, no username yet
        case ready
        case failed(String)
    }

    var status: Status = AppConfig.cloudKitContainerID == nil ? .notConfigured : .checking
    var me: LifterEntry?
    var groups: [LeaderboardGroup] = SocialStore.loadGroups()
    var friendUsernames: [String] = UserDefaults.standard.stringArray(forKey: "friendUsernames") ?? []
    /// Leaderboard members keyed by "friends" or a group code.
    var boards: [String: [LifterEntry]] = [:]
    var isWorking = false
    var lastError: String?

    private var userRecordName: String?
    private var container: CKContainer? {
        AppConfig.cloudKitContainerID.map { CKContainer(identifier: $0) }
    }
    private var db: CKDatabase? { container?.publicCloudDatabase }

    static let friendsBoardID = "friends"

    // MARK: - Setup

    func start() async {
        guard let container else { status = .notConfigured; return }
        do {
            let account = try await container.accountStatus()
            guard account == .available else { status = .noAccount; return }
            let userID = try await container.userRecordID()
            userRecordName = userID.recordName
            if let record = try await fetch(lifterID(for: userID.recordName)) {
                me = Self.entry(from: record, myID: userID.recordName)
                status = .ready
                await refreshBoards()
            } else {
                status = .needsProfile
            }
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// Claims a unique username and creates the user's public lifter profile.
    func createProfile(username raw: String, displayName: String, context: ModelContext) async -> Bool {
        guard let db, let user = userRecordName else { return false }
        let username = Self.clean(raw)
        guard username.count >= 3 else { lastError = "Usernames need at least 3 letters or numbers."; return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let nameID = CKRecord.ID(recordName: "username-\(username)")
            if let existing = try await fetch(nameID), existing["owner"] as? String != lifterID(for: user).recordName {
                lastError = "@\(username) is taken. Try another."
                return false
            }
            let claim = CKRecord(recordType: "Username", recordID: nameID)
            claim["owner"] = lifterID(for: user).recordName
            _ = try await db.modifyRecords(saving: [claim], deleting: [], savePolicy: .allKeys)

            var entry = LifterEntry(id: lifterID(for: user).recordName, displayName: displayName.trimmingCharacters(in: .whitespaces),
                                    username: username, benchKg: 0, squatKg: 0, deadliftKg: 0,
                                    benchTested: false, squatTested: false, deadliftTested: false,
                                    sessionsThisWeek: 0, streakWeeks: 0, updatedAt: .now, isMe: true)
            Self.fillStats(&entry, context: context)
            try await save(entry)
            me = entry
            status = .ready
            await refreshBoards()
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    /// Pushes the latest maxes and consistency to the user's public profile.
    /// Called after workouts, tested maxes, and when the app opens.
    func publish(context: ModelContext) async {
        guard status == .ready, var entry = me else { return }
        Self.fillStats(&entry, context: context)
        guard entry != me else { return }
        do {
            try await save(entry)
            me = entry
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: - Friends

    func addFriend(_ raw: String) async -> Bool {
        let username = Self.clean(raw)
        guard !username.isEmpty, username != me?.username else { return false }
        guard !friendUsernames.contains(username) else { return true }
        isWorking = true
        defer { isWorking = false }
        do {
            guard try await fetch(CKRecord.ID(recordName: "username-\(username)")) != nil else {
                lastError = "No one found with @\(username)."
                return false
            }
            friendUsernames.append(username)
            UserDefaults.standard.set(friendUsernames, forKey: "friendUsernames")
            await refreshBoards()
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    func removeFriend(_ username: String) {
        friendUsernames.removeAll { $0 == username }
        UserDefaults.standard.set(friendUsernames, forKey: "friendUsernames")
        boards[Self.friendsBoardID]?.removeAll { $0.username == username }
    }

    // MARK: - Groups

    func createGroup(name: String) async -> LeaderboardGroup? {
        guard let db, let user = userRecordName else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            var code = Self.newCode()
            // Avoid the (very unlikely) clash with an existing code.
            while try await fetch(CKRecord.ID(recordName: "group-\(code)")) != nil { code = Self.newCode() }
            let record = CKRecord(recordType: "LBGroup", recordID: CKRecord.ID(recordName: "group-\(code)"))
            record["name"] = name
            record["code"] = code
            record["owner"] = lifterID(for: user).recordName
            _ = try await db.save(record)
            let group = LeaderboardGroup(code: code, name: name)
            try await join(group)
            return group
        } catch {
            lastError = Self.describe(error)
            return nil
        }
    }

    func joinGroup(code raw: String) async -> Bool {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 6 else { lastError = "Invite codes have 6 characters."; return false }
        guard !groups.contains(where: { $0.code == code }) else { return true }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let record = try await fetch(CKRecord.ID(recordName: "group-\(code)")) else {
                lastError = "No group with code \(code)."
                return false
            }
            try await join(LeaderboardGroup(code: code, name: record["name"] as? String ?? "Group"))
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    func leaveGroup(_ group: LeaderboardGroup) async {
        guard let db, let user = userRecordName else { return }
        groups.removeAll { $0.code == group.code }
        Self.saveGroups(groups)
        boards[group.code] = nil
        _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: "member-\(group.code)-\(user)"))
    }

    private func join(_ group: LeaderboardGroup) async throws {
        guard let db, let user = userRecordName else { return }
        let record = CKRecord(recordType: "Membership", recordID: CKRecord.ID(recordName: "member-\(group.code)-\(user)"))
        record["groupCode"] = group.code
        record["lifter"] = lifterID(for: user).recordName
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        groups.append(group)
        Self.saveGroups(groups)
        await refreshBoards()
    }

    // MARK: - Leaderboards

    func refreshBoards() async {
        guard status == .ready, let db, let myID = me?.id else { return }
        do {
            // Friends: usernames → owners → lifter records.
            let nameIDs = friendUsernames.map { CKRecord.ID(recordName: "username-\($0)") }
            var friendLifterIDs: [CKRecord.ID] = []
            if !nameIDs.isEmpty {
                let names = try await db.records(for: nameIDs)
                friendLifterIDs = names.values.compactMap { try? $0.get() }.compactMap { $0["owner"] as? String }.map { CKRecord.ID(recordName: $0) }
            }
            boards[Self.friendsBoardID] = try await lifters(friendLifterIDs + [CKRecord.ID(recordName: myID)], myID: myID)

            for group in groups {
                let query = CKQuery(recordType: "Membership", predicate: NSPredicate(format: "groupCode == %@", group.code))
                let result = try await db.records(matching: query, resultsLimit: 200)
                let ids = result.matchResults.compactMap { try? $0.1.get() }.compactMap { $0["lifter"] as? String }.map { CKRecord.ID(recordName: $0) }
                boards[group.code] = try await lifters(ids, myID: myID)
            }
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    func ranked(_ boardID: String, by kind: LeaderboardKind) -> [LifterEntry] {
        (boards[boardID] ?? []).sorted { $0.value(kind) > $1.value(kind) }
    }

    /// A one-line nudge comparing the user with the person just above (or below) them.
    func nudge(unit: WeightUnit) -> String? {
        guard let me else { return nil }
        let candidates = [Self.friendsBoardID] + groups.map(\.code)
        for id in candidates {
            let board = ranked(id, by: .total).filter { $0.totalKg > 0 }
            guard board.count >= 2, let i = board.firstIndex(where: { $0.isMe }) else { continue }
            let name = id == Self.friendsBoardID ? "your friends" : (groups.first { $0.code == id }?.name ?? "your group")
            if i == 0 {
                let gap = me.totalKg - board[1].totalKg
                return "You lead \(name) by \(unit.format(kg: gap)) on the big three total. \(board[1].displayName) is coming."
            } else {
                let ahead = board[i - 1]
                return "#\(i + 1) in \(name). \(unit.format(kg: ahead.totalKg - me.totalKg)) behind \(ahead.displayName) on total."
            }
        }
        return nil
    }

    // MARK: - CloudKit helpers

    private func lifterID(for user: String) -> CKRecord.ID { CKRecord.ID(recordName: "lifter-\(user)") }

    private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
        guard let db else { return nil }
        do {
            return try await db.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func lifters(_ ids: [CKRecord.ID], myID: String) async throws -> [LifterEntry] {
        guard let db, !ids.isEmpty else { return [] }
        let unique = Array(Set(ids))
        let results = try await db.records(for: unique)
        return results.values.compactMap { try? $0.get() }.map { Self.entry(from: $0, myID: myID) }
    }

    private func save(_ entry: LifterEntry) async throws {
        guard let db else { return }
        let record = CKRecord(recordType: "Lifter", recordID: CKRecord.ID(recordName: entry.id))
        record["displayName"] = entry.displayName
        record["username"] = entry.username
        record["bench"] = entry.benchKg
        record["squat"] = entry.squatKg
        record["deadlift"] = entry.deadliftKg
        record["benchTested"] = entry.benchTested ? 1 : 0
        record["squatTested"] = entry.squatTested ? 1 : 0
        record["deadliftTested"] = entry.deadliftTested ? 1 : 0
        record["sessionsThisWeek"] = entry.sessionsThisWeek
        record["streakWeeks"] = entry.streakWeeks
        record["updatedAt"] = entry.updatedAt
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    private static func entry(from r: CKRecord, myID: String) -> LifterEntry {
        LifterEntry(
            id: r.recordID.recordName,
            displayName: r["displayName"] as? String ?? "Lifter",
            username: r["username"] as? String ?? "",
            benchKg: r["bench"] as? Double ?? 0,
            squatKg: r["squat"] as? Double ?? 0,
            deadliftKg: r["deadlift"] as? Double ?? 0,
            benchTested: (r["benchTested"] as? Int ?? 0) == 1,
            squatTested: (r["squatTested"] as? Int ?? 0) == 1,
            deadliftTested: (r["deadliftTested"] as? Int ?? 0) == 1,
            sessionsThisWeek: r["sessionsThisWeek"] as? Int ?? 0,
            streakWeeks: r["streakWeeks"] as? Int ?? 0,
            updatedAt: r["updatedAt"] as? Date ?? .distantPast,
            isMe: r.recordID.recordName == myID)
    }

    /// Fills in maxes and consistency from the local database. Leaves `updatedAt` alone when nothing changed.
    private static func fillStats(_ entry: inout LifterEntry, context: ModelContext) {
        let before = entry
        let bench = PRService.currentMax(for: .bench, in: context)
        let squat = PRService.currentMax(for: .squat, in: context)
        let dead = PRService.currentMax(for: .deadlift, in: context)
        entry.benchKg = (bench?.valueKg ?? 0).rounded(to: 0.1)
        entry.squatKg = (squat?.valueKg ?? 0).rounded(to: 0.1)
        entry.deadliftKg = (dead?.valueKg ?? 0).rounded(to: 0.1)
        entry.benchTested = bench?.kind == .tested1RM
        entry.squatTested = squat?.kind == .tested1RM
        entry.deadliftTested = dead?.kind == .tested1RM

        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).filter(\.isFinished)
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)
        entry.sessionsThisWeek = sessions.filter { week?.contains($0.startedAt) ?? false }.count
        entry.streakWeeks = CoachEngine.trainingLoad(sessions: sessions.sorted { $0.startedAt < $1.startedAt }, now: .now).hardWeeksInARow
        if entry != before { entry.updatedAt = .now }
    }

    private static func clean(_ raw: String) -> String {
        String(raw.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(20))
    }

    private static func newCode() -> String {
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    private static func loadGroups() -> [LeaderboardGroup] {
        guard let data = UserDefaults.standard.data(forKey: "leaderboardGroups"),
              let groups = try? JSONDecoder().decode([LeaderboardGroup].self, from: data) else { return [] }
        return groups
    }

    private static func saveGroups(_ groups: [LeaderboardGroup]) {
        if let data = try? JSONEncoder().encode(groups) { UserDefaults.standard.set(data, forKey: "leaderboardGroups") }
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "You're offline. Leaderboards update when you're back online."
            case .notAuthenticated: return "Sign in to iCloud in the Settings app to use leaderboards."
            case .quotaExceeded: return "iCloud storage is full."
            case .invalidArguments where ck.localizedDescription.contains("Queryable"):
                return "Server setup needed: mark Membership.groupCode as Queryable in CloudKit Console."
            default: return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
