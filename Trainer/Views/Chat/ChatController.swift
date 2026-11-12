import Foundation
import SwiftData
import Observation

/// Sends chat messages to Claude, streams replies into SwiftData, and writes check-in messages.
@MainActor
@Observable
final class ChatController {
    var isStreaming = false
    var lastError: String?
    private var streamTask: Task<Void, Never>?

    /// Maximum past messages sent as conversation history.
    private let historyLimit = 30

    func send(_ text: String, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        context.insert(ChatMessage(role: .user, text: trimmed))
        try? context.save()

        guard KeychainStore.hasAPIKey else {
            let reply = ChatMessage(role: .assistant, text: "Noted. Add your Anthropic API key in Settings and I'll answer properly. Logging, stats and PRs all work without it.")
            context.insert(reply)
            try? context.save()
            return
        }
        generateReply(context: context, trigger: nil, isCheckIn: false)
    }

    /// Writes the trainer's check-in message for a scheduled time. Uses Claude when a key is set,
    /// otherwise a short built-in message so check-ins still work offline / without a key.
    func runCheckIn(time: TimeOfDay, context: ModelContext, health: HealthKitManager.TodayHealth) {
        guard !isStreaming else { return }
        if KeychainStore.hasAPIKey {
            let trigger = "[Scheduled \(time.slot.rawValue) check-in at \(time.label). Write the check-in message now. The app shows quick-reply buttons: \(time.slot.quickReplies.joined(separator: ", ")).]"
            generateReply(context: context, trigger: trigger, isCheckIn: true)
        } else {
            let text = Self.offlineCheckIn(slot: time.slot, context: context, health: health)
            context.insert(ChatMessage(role: .assistant, text: text, isCheckIn: true))
            try? context.save()
        }
    }

    func retryLast(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))) ?? []
        if let failed = all.last, failed.role == .assistant, failed.failed {
            context.delete(failed)
            try? context.save()
        }
        generateReply(context: context, trigger: nil, isCheckIn: false)
    }

    func stop() {
        streamTask?.cancel()
    }

    // MARK: - Internals

    private func generateReply(context: ModelContext, trigger: String?, isCheckIn: Bool) {
        isStreaming = true
        lastError = nil
        let reply = ChatMessage(role: .assistant, text: "", isCheckIn: isCheckIn)
        context.insert(reply)

        let history = buildHistory(context: context, excluding: reply.id, trigger: trigger)
        let health = HealthKitManager.shared.today
        let includeHealth = AppSettings.includeHealthInChat

        streamTask = Task { [weak self] in
            let snapshot = await TrainerContext.snapshot(context: context, health: health, includeHealth: includeHealth)
            let client = AnthropicClient()
            do {
                for try await event in client.stream(stableSystem: TrainerContext.persona, contextSystem: snapshot, messages: history) {
                    switch event {
                    case .text(let t): reply.text += t
                    case .reset: reply.text = ""
                    }
                }
                if Task.isCancelled {
                    if reply.text.isEmpty { context.delete(reply) }
                } else if reply.text.isEmpty {
                    reply.text = "(No reply. Try again.)"
                }
            } catch let error where Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                if reply.text.isEmpty { context.delete(reply) }
            } catch {
                reply.failed = true
                let message = error.localizedDescription
                reply.text = reply.text.isEmpty ? message : reply.text + "\n\n— \(message)"
                self?.lastError = message
            }
            try? context.save()
            self?.isStreaming = false
        }
    }

    /// Recent conversation as API messages. Consecutive messages from the same side are merged
    /// and the list always starts with a user turn, as the API expects.
    private func buildHistory(context: ModelContext, excluding: UUID, trigger: String?) -> [AnthropicClient.Message] {
        var descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = historyLimit + 1
        let recent = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.id != excluding && !$0.failed && !$0.text.isEmpty }
            .reversed()

        var merged: [(role: String, text: String)] = []
        for m in recent {
            let role = m.role.rawValue
            let text = m.isCheckIn && m.role == .assistant ? "[Check-in] \(m.text)" : m.text
            if let last = merged.last, last.role == role {
                merged[merged.count - 1].text += "\n\n" + text
            } else {
                merged.append((role, text))
            }
        }
        if let trigger {
            if let last = merged.last, last.role == "user" {
                merged[merged.count - 1].text += "\n\n" + trigger
            } else {
                merged.append(("user", trigger))
            }
        }
        while let first = merged.first, first.role != "user" { merged.removeFirst() }
        if merged.isEmpty { merged.append(("user", "Hi coach.")) }
        return merged.map { AnthropicClient.Message(role: $0.role, content: $0.text) }
    }

    // MARK: - Check-ins without an API key

    static func offlineCheckIn(slot: CheckInSlot, context: ModelContext, health: HealthKitManager.TodayHealth) -> String {
        let unit = AppSettings.unit
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let finished = sessions.filter(\.isFinished)
        let plans = (try? context.fetch(FetchDescriptor<DayPlan>())) ?? []
        let kinds = Dictionary(plans.map { ($0.day, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let week = TrainingPlanner.plan(days: TrainingPlanner.week(), dayKinds: kinds, finishedSessions: finished)
        let today = week.first(where: \.isToday)
        let todayPlan: String = {
            guard let today else { return "Check the Train tab for your plan." }
            if today.trained { return "You already trained today. Nice." }
            if let t = today.planned { return "Today: \(t.name) (\(t.focus)), about 30 minutes." }
            return today.kind == .free ? "Rest day today. Walk, eat, sleep." : "\(today.kind.label) today, so it's a rest day for lifting."
        }()

        switch slot {
        case .morning:
            let sleep = health.sleepHoursLastNight.map { String(format: "Health shows %.1f hours of sleep. ", $0) } ?? ""
            return "Morning. \(sleep)\(todayPlan) How are you feeling?"
        case .midday:
            var bits: [String] = []
            if let kcal = health.dietaryKcal { bits.append("\(Int(kcal)) kcal") }
            if let p = health.proteinG { bits.append("\(Int(p)) g protein") }
            if let steps = health.steps { bits.append("\(Int(steps)) steps") }
            let sofar = bits.isEmpty ? "" : "So far: " + bits.joined(separator: ", ") + ". "
            return "Midday check. \(sofar)Have you had a proper meal with protein yet?"
        case .evening:
            let trainedToday = finished.contains { Calendar.current.isDateInToday($0.startedAt) }
            var text = trainedToday ? "Good work getting a session in today. " : "Wrapping up the day. "
            if let last = finished.max(by: { $0.startedAt < $1.startedAt }), trainedToday {
                text += "Volume: \(unit.format(kg: last.totalVolumeKg)). "
            }
            if let tomorrow = week.first(where: { Calendar.current.isDateInTomorrow($0.day) }), let t = tomorrow.planned {
                text += "Tomorrow: \(t.name). "
            }
            return text + "How did today go?"
        }
    }
}
