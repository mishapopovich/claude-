import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \ChatMessage.date) private var messages: [ChatMessage]

    @State private var controller = ChatController()
    @State private var draft = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var showClearConfirm = false
    @FocusState private var inputFocused: Bool

    private var lastCheckInSlot: CheckInSlot? {
        guard let last = messages.last, last.isCheckIn, last.role == .assistant else { return nil }
        return TimeOfDay(date: last.date).slot
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !hasKey { NoKeyBanner { router.showSettings = true } }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if messages.isEmpty {
                                emptyState
                            }
                            ForEach(messages) { m in
                                MessageBubble(message: m, isStreaming: controller.isStreaming && m.id == messages.last?.id)
                                    .id(m.id)
                            }
                            if let last = messages.last, last.failed {
                                Button("Try again") { controller.retryLast(context: context) }
                                    .buttonStyle(.bordered)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.last?.text) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                if let slot = lastCheckInSlot, !controller.isStreaming {
                    quickReplies(slot.quickReplies)
                }
                inputBar
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Settings", systemImage: "gear") { router.showSettings = true }
                        Button("Clear chat history", systemImage: "trash", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Clear all chat messages?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    for m in messages { context.delete(m) }
                    try? context.save()
                }
            } message: {
                Text("Messages are only stored on this iPhone. This can't be undone.")
            }
            .onAppear(perform: onAppear)
            .onChange(of: router.pendingCheckIn) { _, pending in
                if pending { onAppear() }
            }
            .onChange(of: router.showSettings) { _, showing in
                if !showing { hasKey = KeychainStore.hasAPIKey }
            }
        }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Your coach").font(.title2.bold())
            Text("Ask about your program, a lift, food, recovery around shifts, or what to do today. The coach sees your recent workouts, PRs and Apple Health numbers.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["What should I do today?", "I just finished a 24h shift. Train or rest?", "How's my squat progressing?", "Am I eating enough protein?"], id: \.self) { q in
                    Button(q) { send(q) }
                        .buttonStyle(.bordered)
                        .disabled(!hasKey)
                }
            }
        }
        .padding(.vertical, 40)
    }

    private func quickReplies(_ replies: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(replies, id: \.self) { r in
                    Button(r) { send(r) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(hasKey ? "Message your coach" : "Add an API key in Settings to chat", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
                .focused($inputFocused)
            if controller.isStreaming {
                Button { controller.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 32))
                }
                .accessibilityLabel("Stop")
            } else {
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func send(_ text: String) {
        controller.send(text, context: context)
        draft = ""
    }

    private func onAppear() {
        hasKey = KeychainStore.hasAPIKey
        // Write a due check-in (from a notification tap, or a scheduled time that passed).
        let schedule = CheckInSchedule.load()
        let todayKind = CheckInSync.dayKinds(context: context)[Calendar.current.startOfDay(for: .now)]
        if let due = CheckInScheduler.dueCheckIn(schedule: schedule, dayKind: todayKind) {
            CheckInScheduler.markHandled(due.1)
            controller.runCheckIn(time: due.0, context: context, health: health.today)
        } else if router.pendingCheckIn, !controller.isStreaming, messages.last?.isCheckIn != true {
            // Opened from a notification but the slot was already handled: write a fresh one for now.
            controller.runCheckIn(time: TimeOfDay(date: .now), context: context, health: health.today)
        }
        router.pendingCheckIn = false

        if let reply = router.pendingQuickReply {
            router.pendingQuickReply = nil
            // Let the check-in message finish first, then send the reply.
            Task {
                while controller.isStreaming { try? await Task.sleep(for: .milliseconds(300)) }
                send(reply)
            }
        }
    }
}

struct NoKeyBanner: View {
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The coach needs your Anthropic API key", systemImage: "key.fill").font(.headline)
            Text("Create a key at console.anthropic.com and paste it in Settings. The API is billed separately, pay as you go. A Claude Pro or Max subscription doesn't include API access.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Workouts, stats, PRs and check-in reminders all work without a key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Add API key", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming = false

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if message.isCheckIn {
                    Label(TimeOfDay(date: message.date).slot.title, systemImage: "bell")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if message.text.isEmpty && isStreaming {
                    ProgressView().padding(.vertical, 4)
                } else {
                    Text(rendered)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(background)
            )
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var background: Color {
        if message.failed { return Color.red.opacity(0.15) }
        return message.role == .user ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }
}
