import SwiftUI
import SwiftData

struct LeaderboardView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    @State private var boardID = SocialStore.friendsBoardID
    @State private var kind: LeaderboardKind = .total
    @State private var showAddFriend = false
    @State private var showGroupSheet = false

    var body: some View {
        NavigationStack {
            Group {
                switch social.status {
                case .notConfigured: NotConfiguredView()
                case .checking: ProgressView("Connecting to iCloud…")
                case .noAccount:
                    ContentUnavailableView("Sign in to iCloud", systemImage: "icloud.slash",
                                           description: Text("Leaderboards use your iCloud account. Sign in from the iPhone Settings app, then come back."))
                case .needsProfile: ProfileSetupView()
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't reach iCloud", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await social.start() } }
                    }
                case .ready: boardList
                }
            }
            .navigationTitle("Leaderboard")
            .toolbar {
                if social.status == .ready {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Add a friend", systemImage: "person.badge.plus") { showAddFriend = true }
                            Button("Create or join a group", systemImage: "person.3") { showGroupSheet = true }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) { AddFriendSheet().presentationDetents([.medium]) }
            .sheet(isPresented: $showGroupSheet) { GroupSheet().presentationDetents([.medium, .large]) }
            .task {
                if social.status == .checking { await social.start() }
            }
        }
    }

    private var boardList: some View {
        let entries = social.ranked(boardID, by: kind)
        return List {
            Section {
                Picker("Board", selection: $boardID) {
                    Text("Friends").tag(SocialStore.friendsBoardID)
                    ForEach(social.groups) { g in Text(g.name).tag(g.code) }
                }
                Picker("Ranking", selection: $kind) {
                    ForEach(LeaderboardKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if let nudge = social.nudge(unit: unit) {
                Section {
                    Label(nudge, systemImage: "flame.fill").foregroundStyle(Theme.blue)
                }
            }

            Section {
                if entries.count <= 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(boardID == SocialStore.friendsBoardID ? "Add friends to start competing." : "Share the invite code so others can join.")
                            .font(.headline)
                        Text(boardID == SocialStore.friendsBoardID
                             ? "Ask them for their @username (they find it on this tab), or create a group and send the code."
                             : "Code: \(boardID)")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    LeaderboardRow(rank: i + 1, entry: e, kind: kind, unit: unit)
                        .swipeActions {
                            if boardID == SocialStore.friendsBoardID && !e.isMe {
                                Button("Remove", role: .destructive) { social.removeFriend(e.username) }
                            }
                        }
                }
            } footer: {
                Text(kind == .consistency
                     ? "Streak = weeks in a row hitting your session target, then sessions this week."
                     : "Maxes are your best tested or estimated 1RM. Only lifts and totals are shared; body weight never is.")
            }

            if let group = social.groups.first(where: { $0.code == boardID }) {
                Section {
                    ShareLink(item: "Join my MP Coaching group \"\(group.name)\" with code \(group.code)") {
                        Label("Invite with code \(group.code)", systemImage: "square.and.arrow.up")
                    }
                    Button("Leave group", role: .destructive) {
                        Task {
                            await social.leaveGroup(group)
                            boardID = SocialStore.friendsBoardID
                        }
                    }
                }
            }

            if let me = social.me {
                Section("You") {
                    LabeledContent("Username", value: "@\(me.username)")
                    if me.totalKg > 0 {
                        ShareLink(item: PRCardRenderer.render(title: "Big three total", value: unit.format(kg: me.totalKg),
                                                              detail: "Bench \(unit.format(kg: me.benchKg, withUnit: false)) · Squat \(unit.format(kg: me.squatKg, withUnit: false)) · Deadlift \(unit.format(kg: me.deadliftKg, withUnit: false))",
                                                              name: me.displayName),
                                  preview: SharePreview("My big three total", image: Image(systemName: "trophy"))) {
                            Label("Share my total", systemImage: "photo")
                        }
                    }
                }
            }

            if let error = social.lastError {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.warn) }
            }
        }
        .refreshable {
            await social.publish(context: context)
            await social.refreshBoards()
        }
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let entry: LifterEntry
    let kind: LeaderboardKind
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 30, height: 30)
                .background(Circle().fill(rank == 1 ? Theme.blue : Color(.tertiarySystemFill)))
                .foregroundStyle(rank == 1 ? .white : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isMe ? "\(entry.displayName) (you)" : entry.displayName)
                    .font(.body.weight(entry.isMe ? .bold : .regular))
                Text("@\(entry.username) · updated \(entry.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(valueText).font(.headline).monospacedDigit()
                if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .listRowBackground(entry.isMe ? Theme.blueFaint : nil)
    }

    private var valueText: String {
        switch kind {
        case .consistency: return "\(entry.streakWeeks) wk · \(entry.sessionsThisWeek)"
        default:
            let v = entry.value(kind)
            return v > 0 ? unit.format(kg: v) : "–"
        }
    }

    private var note: String? {
        switch kind {
        case .bench: entry.benchTested ? "tested" : (entry.benchKg > 0 ? "est." : nil)
        case .squat: entry.squatTested ? "tested" : (entry.squatKg > 0 ? "est." : nil)
        case .deadlift: entry.deadliftTested ? "tested" : (entry.deadliftKg > 0 ? "est." : nil)
        default: nil
        }
    }
}

struct ProfileSetupView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.userName) private var userName = ""
    @State private var username = ""
    @State private var displayName = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(Theme.blue)
                    Text("Compete with friends").font(.title2.bold())
                    Text("Rank on bench, squat, deadlift, the big three total, and training streaks. Only lifts, totals and how many sessions you've done are shared. Body weight and Health data never leave your phone.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section("Your public profile") {
                TextField("Display name", text: $displayName)
                TextField("Username (letters, numbers, _)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if let error = social.lastError {
                Text(error).foregroundStyle(Theme.warn)
            }
            Button {
                Task { _ = await social.createProfile(username: username, displayName: displayName, context: context) }
            } label: {
                if social.isWorking { ProgressView() } else { Text("Create profile").bold() }
            }
            .disabled(username.count < 3 || displayName.trimmingCharacters(in: .whitespaces).isEmpty || social.isWorking)
        }
        .onAppear {
            if displayName.isEmpty { displayName = userName }
        }
    }
}

struct AddFriendSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("@username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let me = social.me { Text("Your username is @\(me.username). Share it so friends can add you.") }
                }
                if let error = social.lastError { Text(error).foregroundStyle(Theme.warn) }
            }
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { if await social.addFriend(username) { dismiss() } }
                    }
                    .disabled(username.isEmpty || social.isWorking)
                }
            }
        }
    }
}

struct GroupSheet: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var code = ""
    @State private var created: LeaderboardGroup?

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    Section("Group created") {
                        LabeledContent("Invite code", value: created.code)
                            .font(.title3.monospaced())
                        ShareLink(item: "Join my MP Coaching group \"\(created.name)\" with code \(created.code)") {
                            Label("Send invite", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section("Create a group") {
                        TextField("Group name (e.g. Station 12)", text: $newName)
                        Button("Create") {
                            Task { created = await social.createGroup(name: newName.trimmingCharacters(in: .whitespaces)) }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || social.isWorking)
                    }
                    Section("Join with a code") {
                        TextField("6-character code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Join") {
                            Task { if await social.joinGroup(code: code) { dismiss() } }
                        }
                        .disabled(code.count < 6 || social.isWorking)
                    }
                }
                if let error = social.lastError { Text(error).foregroundStyle(Theme.warn) }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct NotConfiguredView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "trophy.fill").font(.system(size: 44)).foregroundStyle(Theme.blue)
                Text("Leaderboards are almost ready").font(.title2.bold())
                Text("Friends and group leaderboards run on iCloud (CloudKit), which needs a paid Apple Developer account. This build was made without it.")
                    .foregroundStyle(.secondary)
                Text("To turn it on (developer steps):").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Xcode → MPCoaching target → Signing & Capabilities → + Capability → iCloud → tick CloudKit and add a container.")
                    Text("2. Paste the container id into AppConfig.cloudKitContainerID.")
                    Text("3. Run once, then in CloudKit Console mark Membership.groupCode as Queryable.")
                }
                .font(.subheadline)
                Text("Everything else in the app works without it.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

/// Today-screen nudge: where you stand against friends.
struct LeaderboardNudgeSection: View {
    @Environment(SocialStore.self) private var social
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    var body: some View {
        if let nudge = social.nudge(unit: unit) {
            Section {
                Button { router.tab = .leaderboard } label: {
                    Label(nudge, systemImage: "flame.fill")
                        .foregroundStyle(Theme.blue)
                }
            }
        }
    }
}
