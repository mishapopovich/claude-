import Foundation
import UserNotifications

struct TimeOfDay: Codable, Hashable, Comparable, Identifiable {
    var hour: Int
    var minute: Int

    var id: Int { hour * 60 + minute }
    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.minutesSinceMidnight < b.minutesSinceMidnight }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    func date(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var label: String { date(on: .now).formatted(date: .omitted, time: .shortened) }

    /// Morning, midday or evening, which decides what the check-in asks about.
    var slot: CheckInSlot {
        switch hour {
        case ..<11: .morning
        case 11..<16: .midday
        default: .evening
        }
    }
}

enum CheckInSlot: String, Codable {
    case morning, midday, evening

    var title: String {
        switch self {
        case .morning: "Morning check-in"
        case .midday: "Midday check-in"
        case .evening: "Evening wrap-up"
        }
    }

    var notificationBody: String {
        switch self {
        case .morning: "How did you sleep? Tap to see today's plan."
        case .midday: "How's food and movement going so far today?"
        case .evening: "Quick wrap-up of today, and a look at tomorrow."
        }
    }

    var quickReplies: [String] {
        switch self {
        case .morning: ["Slept well", "Slept badly", "Sore", "Coming off a shift", "Rest day"]
        case .midday: ["Ate well", "Need protein", "Busy day", "Trained", "Rest day"]
        case .evening: ["Trained", "Rest day", "Sore", "Ate well", "Tired"]
        }
    }
}

struct CheckInSchedule: Codable, Equatable {
    enum Mode: Codable, Equatable {
        case preset(Int)   // 1–4 times a day
        case custom
    }

    var enabled: Bool = true
    var mode: Mode = .preset(2)
    var customTimes: [TimeOfDay] = [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 19, minute: 30)]
    var quietHoursEnabled: Bool = true
    var quietStart = TimeOfDay(hour: 22, minute: 0)
    var quietEnd = TimeOfDay(hour: 7, minute: 0)
    /// Weekdays with check-ins (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int> = Set(1...7)
    var muteOn24hShift: Bool = true
    var muteOn12hShift: Bool = false

    static func presetTimes(_ n: Int) -> [TimeOfDay] {
        switch n {
        case 1: [TimeOfDay(hour: 8, minute: 0)]
        case 2: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 19, minute: 30)]
        case 3: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 13, minute: 0), TimeOfDay(hour: 19, minute: 30)]
        default: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 12, minute: 0), TimeOfDay(hour: 16, minute: 0), TimeOfDay(hour: 20, minute: 30)]
        }
    }

    /// The times that apply, sorted, before quiet hours are removed.
    var times: [TimeOfDay] {
        switch mode {
        case .preset(let n): CheckInSchedule.presetTimes(n)
        case .custom: Array(Set(customTimes)).sorted()
        }
    }

    func isQuiet(_ t: TimeOfDay) -> Bool {
        guard quietHoursEnabled else { return false }
        let m = t.minutesSinceMidnight, s = quietStart.minutesSinceMidnight, e = quietEnd.minutesSinceMidnight
        if s == e { return false }
        return s < e ? (m >= s && m < e) : (m >= s || m < e)
    }

    /// Times that will actually fire on a given day.
    func activeTimes(on day: Date, dayKind: DayKind?) -> [TimeOfDay] {
        guard enabled else { return [] }
        let weekday = Calendar.current.component(.weekday, from: day)
        guard weekdays.contains(weekday) else { return [] }
        if dayKind == .shift24 && muteOn24hShift { return [] }
        if dayKind == .shift12 && muteOn12hShift { return [] }
        return times.filter { !isQuiet($0) }
    }

    // MARK: Persistence

    static func load() -> CheckInSchedule {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.checkInSchedule),
              let s = try? JSONDecoder().decode(CheckInSchedule.self, from: data) else { return CheckInSchedule() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SettingsKey.checkInSchedule)
        }
    }
}

/// Schedules check-in reminders as local notifications. The trainer's actual message is written
/// when the user opens the app (no server needed), so the notification itself is a fixed prompt.
enum CheckInScheduler {
    static let categoryID = "CHECKIN"
    static let idPrefix = "checkin-"
    /// iOS keeps at most 64 pending notifications per app; leave room for the rest timer.
    private static let maxPending = 60

    static func registerCategories() {
        let replies = ["Slept well", "Sore", "Rest day"].enumerated().map { i, title in
            UNNotificationAction(identifier: "reply-\(i)-\(title)", title: title, options: [.foreground])
        }
        let category = UNNotificationCategory(identifier: categoryID, actions: replies, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuilds all pending check-in notifications for the coming days.
    /// Called on launch, when returning to the app, and whenever the schedule or week plan changes.
    static func reschedule(schedule: CheckInSchedule, dayKinds: [Date: DayKind]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) })

        guard schedule.enabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let perDay = max(1, schedule.times.count)
        let daysAhead = min(14, max(1, maxPending / perDay))
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var added = 0

        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            for time in schedule.activeTimes(on: day, dayKind: dayKinds[day]) {
                let fireDate = time.date(on: day)
                guard fireDate > .now, added < maxPending else { continue }
                let content = UNMutableNotificationContent()
                content.title = time.slot.title
                content.body = time.slot.notificationBody
                content.sound = .default
                content.categoryIdentifier = categoryID
                content.userInfo = ["slot": time.slot.rawValue, "fireDate": fireDate.timeIntervalSince1970]
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = idPrefix + String(Int(fireDate.timeIntervalSince1970))
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                added += 1
            }
        }
    }

    /// The most recent check-in time today that has passed and hasn't been answered yet (within 4 hours).
    static func dueCheckIn(schedule: CheckInSchedule, dayKind: DayKind?, now: Date = .now) -> (TimeOfDay, String)? {
        let times = schedule.activeTimes(on: now, dayKind: dayKind)
        guard let last = times.last(where: { $0.date(on: now) <= now }) else { return nil }
        guard now.timeIntervalSince(last.date(on: now)) < 4 * 3600 else { return nil }
        let key = handledKey(for: last, on: now)
        guard !UserDefaults.standard.bool(forKey: key) else { return nil }
        return (last, key)
    }

    static func handledKey(for time: TimeOfDay, on day: Date) -> String {
        let d = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "checkin-handled-\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)-\(time.minutesSinceMidnight)"
    }

    static func markHandled(_ key: String) {
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: Rest timer

    static let restTimerID = "rest-timer"

    static func scheduleRestTimer(seconds: Int, nextLabel: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restTimerID])
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = nextLabel
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: restTimerID, content: content, trigger: trigger))
    }

    static func cancelRestTimer() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restTimerID])
    }
}
