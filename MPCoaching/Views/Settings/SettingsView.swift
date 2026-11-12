import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @AppStorage(SettingsKey.model) private var model = ClaudeModel.defaultID
    @AppStorage(SettingsKey.restSeconds) private var restSeconds = 90
    @AppStorage(SettingsKey.sessionsPerWeek) private var sessionsPerWeek = 2
    @AppStorage(SettingsKey.healthIncludeInChat) private var includeHealthInChat = true
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.userContext) private var userContext = ""

    @State private var keyDraft = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var keyTest: String?
    @State private var testingKey = false
    @State private var preferredDays = AppSettings.preferredWeekdays
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                apiSection

                Section("Coach model") {
                    Picker("Model", selection: $model) {
                        ForEach(ClaudeModel.options) { m in
                            Text(m.name).tag(m.id)
                        }
                        if !ClaudeModel.options.contains(where: { $0.id == model }) {
                            Text(model).tag(model)
                        }
                    }
                    if let m = ClaudeModel.options.first(where: { $0.id == model }) {
                        Text(m.note).font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("Or type a model id", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                }

                Section {
                    TextField("Your name", text: $userName)
                    TextField("About you: schedule, goals, injuries to work around…", text: $userContext, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("About you")
                } footer: {
                    Text("Shared with the coach so its advice fits your life.")
                }

                Section("Training") {
                    Picker("Units", selection: $unit) {
                        ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Rest timer: \(restSeconds / 60):\(String(format: "%02d", restSeconds % 60))", value: $restSeconds, in: 15...600, step: 15)
                    Stepper("Sessions per week: \(sessionsPerWeek)", value: $sessionsPerWeek, in: 1...6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preferred training days")
                        WeekdayPicker(selection: $preferredDays)
                    }
                    .onChange(of: preferredDays) { _, v in AppSettings.preferredWeekdays = v }
                }

                Section {
                    NavigationLink {
                        CheckInSettingsView()
                    } label: {
                        Label("Check-in schedule", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        HealthPermissionsView()
                    } label: {
                        Label("Apple Health", systemImage: "heart.text.square")
                    }
                    Toggle("Share Health numbers with the coach", isOn: $includeHealthInChat)
                } footer: {
                    Text("Health data stays on this iPhone and in Apple Health. Only when you've added your own API key, the coach chat includes recent summary numbers (sleep, steps, food totals) in what it sends to Anthropic.")
                }

                Section("Your data") {
                    Button {
                        exportURL = DataExport.write(context: context)
                    } label: {
                        Label("Export all data (JSON)", systemImage: "square.and.arrow.up")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share export file", systemImage: "doc")
                        }
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                }

                Section {
                    Text("No analytics, no tracking. Workouts, chat and weights are stored only on this iPhone. Your API key is kept in the Keychain and only ever sent to api.anthropic.com.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete everything?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete all workouts, weights, PRs and chat", role: .destructive) { DataExport.deleteAll(context: context) }
            } message: {
                Text("This removes all app data from this iPhone. Data already saved to Apple Health stays there. Export first if you want a copy.")
            }
        }
    }

    private var apiSection: some View {
        Section {
            if hasKey {
                Label("API key saved in Keychain", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Button {
                    Task { await testKey() }
                } label: {
                    if testingKey { ProgressView() } else { Text("Test connection") }
                }
                .disabled(testingKey)
                if let keyTest { Text(keyTest).font(.footnote).foregroundStyle(.secondary) }
                Button("Remove key", role: .destructive) {
                    KeychainStore.setAPIKey(nil)
                    hasKey = false
                    keyTest = nil
                }
            } else {
                SecureField("sk-ant-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Save key") {
                    hasKey = KeychainStore.setAPIKey(keyDraft) && KeychainStore.hasAPIKey
                    keyDraft = ""
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).count < 20)
            }
            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                Label("Get a key at console.anthropic.com", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Anthropic API key")
        } footer: {
            Text("The coach uses the Anthropic API with your own key, billed pay-as-you-go on the Anthropic Console. A Claude Pro or Max chat subscription does not include API access.")
        }
    }

    private func testKey() async {
        testingKey = true
        defer { testingKey = false }
        do {
            var client = AnthropicClient()
            client.maxTokens = 2000
            let reply = try await client.complete(
                stableSystem: "Reply with the single word: ready",
                contextSystem: "Connection test.",
                messages: [.init(role: "user", content: "Connection test")])
            keyTest = "Connected to \(model). Reply: \(reply.prefix(40))"
        } catch {
            keyTest = error.localizedDescription
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        // Start the row on the locale's first weekday.
        let first = Calendar.current.firstWeekday
        let order = (0..<7).map { (first - 1 + $0) % 7 + 1 }
        HStack {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? Color.accentColor : Color(.secondarySystemBackground)))
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct HealthPermissionsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            if !health.isAvailable {
                Text("Apple Health isn't available on this device.").foregroundStyle(.secondary)
            }
            Section {
                ForEach(HealthKitManager.DataGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(group.title, systemImage: group.symbol).font(.headline)
                            Spacer()
                            if health.hasAsked(group) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        Text(group.why).font(.subheadline).foregroundStyle(.secondary)
                        Button(health.hasAsked(group) ? "Review access" : "Connect") {
                            Task {
                                await health.request(group)
                                if group == .body { await BodyWeightSync.importFromHealth(context: context) }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Each one is optional. Skip any you don't want and the rest of the app works normally. To change a choice later, open the Health app → your profile → Apps → this app.")
            }
        }
        .navigationTitle("Apple Health")
    }
}

/// JSON export and full delete.
@MainActor
enum DataExport {
    static func write(context: ModelContext) -> URL? {
        let unit = AppSettings.unit
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let weights = (try? context.fetch(FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let records = (try? context.fetch(FetchDescriptor<PersonalRecord>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let chat = (try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let iso = ISO8601DateFormatter()

        let json: [String: Any] = [
            "exportedAt": iso.string(from: .now),
            "displayUnit": unit.rawValue,
            "note": "All weights are in kilograms.",
            "workouts": sessions.map { s in
                [
                    "id": s.id.uuidString,
                    "name": s.templateName,
                    "startedAt": iso.string(from: s.startedAt),
                    "endedAt": s.endedAt.map { iso.string(from: $0) } ?? "",
                    "sets": s.sets.sorted { $0.completedAt < $1.completedAt }.map { set in
                        [
                            "exercise": set.exerciseID,
                            "setNumber": set.setNumber,
                            "weightKg": set.weightKg,
                            "reps": set.reps,
                            "skipped": set.skipped,
                            "completedAt": iso.string(from: set.completedAt),
                        ] as [String: Any]
                    },
                ] as [String: Any]
            },
            "bodyWeight": weights.map { ["date": iso.string(from: $0.date), "weightKg": $0.weightKg, "source": $0.sourceRaw] as [String: Any] },
            "testedMaxes": records.map { ["exercise": $0.exerciseID, "weightKg": $0.weightKg, "date": iso.string(from: $0.date), "kind": $0.kindRaw] as [String: Any] },
            "chat": chat.map { ["role": $0.roleRaw, "text": $0.text, "date": iso.string(from: $0.date), "checkIn": $0.isCheckIn] as [String: Any] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let name = "mp-coaching-export-\(Date.now.formatted(.iso8601.year().month().day())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func deleteAll(context: ModelContext) {
        try? context.delete(model: ExerciseSet.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: BodyWeightEntry.self)
        try? context.delete(model: PersonalRecord.self)
        try? context.delete(model: ChatMessage.self)
        try? context.delete(model: DayPlan.self)
        try? context.save()
        AppRouter.shared.activeSession = nil
    }
}
