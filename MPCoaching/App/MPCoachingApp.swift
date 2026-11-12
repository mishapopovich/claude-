import SwiftUI
import SwiftData
import UserNotifications

@main
struct MPCoachingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter.shared
    @State private var health = HealthKitManager.shared

    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(AppSchema.models))
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(health)
        }
        .modelContainer(Self.container)
    }
}

enum AppTab: Hashable {
    case today, train, chat, library, progress
}

/// App-wide navigation state, also driven by notification taps.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .today
    /// The workout being logged right now (presented full screen).
    var activeSession: WorkoutSession?
    /// Set when the user opened the app from a check-in notification.
    var pendingCheckIn = false
    /// Quick reply chosen straight from the notification, sent once the chat appears.
    var pendingQuickReply: String?
    var showSettings = false
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        CheckInScheduler.registerCategories()
        return true
    }

    // Show banners while the app is open too (e.g. rest timer while on another tab).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == CheckInScheduler.categoryID else { return }
        let action = response.actionIdentifier
        var reply: String?
        if action.hasPrefix("reply-") {
            // identifier format: reply-<index>-<title>
            reply = action.split(separator: "-", maxSplits: 2).last.map(String.init)
        }
        await MainActor.run {
            let router = AppRouter.shared
            router.tab = .chat
            router.pendingCheckIn = true
            router.pendingQuickReply = reply
        }
    }
}
