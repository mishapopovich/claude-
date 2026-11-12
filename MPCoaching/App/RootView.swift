import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            TrainView()
                .tabItem { Label("Train", systemImage: "dumbbell") }
                .tag(AppTab.train)
            ChatView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.chat)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)
            ProgressHubView()
                .tabItem { Label("PRs", systemImage: "trophy") }
                .tag(AppTab.progress)
        }
        .fullScreenCover(item: $router.activeSession) { session in
            SessionView(session: session)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task {
            await refreshEverything()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshEverything() }
            }
        }
    }

    private func refreshEverything() async {
        await health.refreshToday()
        await BodyWeightSync.importFromHealth(context: context)
        await CheckInSync.reschedule(context: context)
    }
}

/// Helpers that glue SwiftData to services.
@MainActor
enum CheckInSync {
    static func dayKinds(context: ModelContext) -> [Date: DayKind] {
        let plans = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        return Dictionary(plans.map { ($0.day, $0.kind) }, uniquingKeysWith: { a, _ in a })
    }

    static func reschedule(context: ModelContext) async {
        await CheckInScheduler.reschedule(schedule: CheckInSchedule.load(), dayKinds: dayKinds(context: context))
    }
}

@MainActor
enum BodyWeightSync {
    /// Pulls weigh-ins from Apple Health (e.g. a smart scale) into the local weight log, once each.
    static func importFromHealth(context: ModelContext) async {
        let health = HealthKitManager.shared
        guard health.hasAsked(.body) else { return }
        let since = Calendar.current.date(byAdding: .year, value: -2, to: .now) ?? .distantPast
        let samples = await health.bodyMassSamples(since: since)
        guard !samples.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        let known = Set(existing.compactMap(\.healthKitUUID))
        for s in samples where !known.contains(s.uuid) {
            context.insert(BodyWeightEntry(date: s.date, weightKg: s.kg, source: .healthKit, healthKitUUID: s.uuid))
        }
        try? context.save()
    }
}
