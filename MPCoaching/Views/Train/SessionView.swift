import SwiftUI
import SwiftData

/// The guided workout. Everything needed between sets is on this one screen: the exercise picture,
/// the prescription, last time's numbers, the set entry pad, one big Log button, and the rest timer.
struct SessionView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs
    @AppStorage(SettingsKey.restSeconds) private var restSeconds = 90

    @State private var currentID: String = ""
    @State private var weightText = "0"
    @State private var repsText = "0"
    @State private var field: SetEntryPad.Field = .weight
    @State private var fresh = true
    @State private var restEndsAt: Date?
    @State private var prMessage: String?
    @State private var editingSet: ExerciseSet?
    @State private var showDetail: Exercise?
    @State private var showAddExercise = false
    @State private var showFinishConfirm = false
    @State private var showDiscardConfirm = false
    @State private var showSummary = false

    private var logic: SessionLogic { SessionLogic(session: session, context: context) }
    private var exercise: Exercise? { ExerciseCatalog.exercise(currentID) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                exerciseStrip
                Divider()
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        setChips
                        if let restEndsAt { restBanner(until: restEndsAt) }
                        if let prMessage { prBanner(prMessage) }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                entryArea
            }
            .navigationTitle(session.templateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $editingSet) { set in
                EditSetSheet(set: set, unit: unit) { try? context.save() }
                    .presentationDetents([.medium])
            }
            .sheet(item: $showDetail) { ex in
                NavigationStack { ExerciseDetailView(exercise: ex) }
            }
            .sheet(isPresented: $showAddExercise) {
                ExercisePickerSheet { ex in
                    if !session.exerciseOrder.contains(ex.id) { session.exerciseOrder.append(ex.id) }
                    select(ex.id)
                    try? context.save()
                }
            }
            .fullScreenCover(isPresented: $showSummary) {
                SessionSummaryView(session: session) {
                    showSummary = false
                    router.activeSession = nil
                }
            }
            .confirmationDialog("Finish workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
                Button("Finish and save") { finish() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Some planned sets aren't logged yet. They'll just be left out.")
            }
            .confirmationDialog("Discard this workout?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { discard() }
            } message: {
                Text("All sets logged in this session will be deleted.")
            }
        }
        .onAppear {
            if currentID.isEmpty {
                select(session.exerciseOrder.first(where: { !logic.isDone($0) }) ?? session.exerciseOrder.first ?? "")
            }
        }
    }

    // MARK: - Top: exercise strip

    private var exerciseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.exerciseOrder, id: \.self) { id in
                        let done = logic.logged(id).count
                        let total = max(logic.plannedSetCount(id), done)
                        Button { select(id) } label: {
                            HStack(spacing: 4) {
                                if logic.isDone(id) { Image(systemName: "checkmark.circle.fill") }
                                Text(ExerciseCatalog.name(id)).lineLimit(1)
                                Text("\(done)/\(total)").foregroundStyle(.secondary)
                            }
                            .font(.footnote.weight(id == currentID ? .bold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(id == currentID ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .id(id)
                    }
                    Button { showAddExercise = true } label: {
                        Label("Add", systemImage: "plus")
                            .font(.footnote)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: currentID) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: - Exercise header

    @ViewBuilder
    private var header: some View {
        if let exercise {
            HStack(alignment: .top, spacing: 12) {
                Button { showDetail = exercise } label: {
                    ExercisePicture(exercise: exercise)
                        .frame(width: 96, height: 96)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .padding(4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows how to do this exercise")

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.title3.bold())
                    if let plan = logic.planned(exercise.id) {
                        Text(plan.prescription).font(.headline).foregroundStyle(Color.accentColor)
                        if let note = plan.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("\(logic.plannedSetCount(exercise.id)) sets").font(.headline).foregroundStyle(Color.accentColor)
                    }
                    let last = logic.lastTime(exercise.id).filter { !$0.skipped }
                    if !last.isEmpty {
                        Text("Last time: " + last.map { "\(unit.format(kg: $0.weightKg, withUnit: false))×\($0.reps)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if logic.logged(exercise.id).isEmpty, let hint = logic.progressionHint(exercise.id, unit: unit) {
                        Button {
                            weightText = WeightUnit.number(hint)
                            fresh = true
                        } label: {
                            Label("Top of range last time. Try \(WeightUnit.number(hint)) \(unit.rawValue)", systemImage: "arrow.up.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            ContentUnavailableView("Add an exercise", systemImage: "plus.circle", description: Text("Tap Add above to pick from the library."))
        }
    }

    // MARK: - Set chips

    @ViewBuilder
    private var setChips: some View {
        if let exercise {
            let sets = logic.logged(exercise.id)
            let plannedCount = logic.plannedSetCount(exercise.id)
            // Once the plan is done, show one "Extra" slot: logging again adds a set beyond the plan.
            let planned = max(plannedCount, sets.count + (logic.isDone(exercise.id) ? 1 : 0))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<planned, id: \.self) { i in
                        if i < sets.count {
                            let s = sets[i]
                            Button { editingSet = s } label: {
                                VStack(spacing: 2) {
                                    Text("Set \(i + 1)").font(.caption2).foregroundStyle(.secondary)
                                    if s.skipped {
                                        Text("Skipped").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                    } else {
                                        Text("\(unit.format(kg: s.weightKg, withUnit: false))×\(s.reps)").font(.footnote.weight(.semibold))
                                    }
                                }
                                .frame(minWidth: 64, minHeight: 44)
                                .padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(s.skipped ? 0.08 : 0.18)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Tap to edit")
                        } else {
                            VStack(spacing: 2) {
                                Text("Set \(i + 1)").font(.caption2).foregroundStyle(.secondary)
                                Text(i >= plannedCount ? "Extra" : (i == sets.count ? "Now" : "–")).font(.footnote.weight(.semibold))
                            }
                            .frame(minWidth: 64, minHeight: 44)
                            .padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(i == sets.count ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: i == sets.count ? 2 : 1))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rest timer and PR banner

    private func restBanner(until end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
            HStack {
                Image(systemName: left > 0 ? "timer" : "bell.badge.fill")
                VStack(alignment: .leading) {
                    Text(left > 0 ? "Rest" : "Rest's up. Go!").font(.caption).foregroundStyle(.secondary)
                    Text(left > 0 ? String(format: "%d:%02d", left / 60, left % 60) : "0:00")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Button("+15s") {
                    restEndsAt = (restEndsAt ?? .now).addingTimeInterval(15)
                    rescheduleRestNotification()
                }
                .buttonStyle(.bordered)
                Button("Skip") {
                    restEndsAt = nil
                    CheckInScheduler.cancelRestTimer()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill((left > 0 ? Theme.blue : Theme.good).opacity(0.15)))
        }
    }

    private func prBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "trophy.fill").foregroundStyle(Theme.blue)
            Text(text).font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.blue.opacity(0.22)))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Entry area (pinned to the bottom for thumb reach)

    private var entryArea: some View {
        VStack(spacing: 10) {
            if let exercise {
                SetEntryPad(
                    weightText: $weightText, repsText: $repsText, field: $field, fresh: $fresh,
                    unit: unit,
                    weightStep: unit == .kg ? 2.5 : exercise.incrementLbs,
                    isBodyweight: exercise.isBodyweight)

                HStack(spacing: 10) {
                    Button { skipSet() } label: {
                        Text("Skip").frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .frame(width: 88)

                    if logic.allDone {
                        Button { finish() } label: {
                            Label("Finish workout", systemImage: "flag.checkered")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button { logSet() } label: {
                            Text("Log set \(logic.logged(exercise.id).count + 1)")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((Int(repsText) ?? 0) <= 0)
                    }
                }
                if logic.allDone {
                    Button("Log another set of \(exercise.name)") { logSet() }
                        .font(.footnote)
                        .disabled((Int(repsText) ?? 0) <= 0)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                router.activeSession = nil
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Minimize workout")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(session.templateName).font(.headline)
                Text(session.startedAt, style: .timer).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Finish workout", systemImage: "flag.checkered") {
                    if logic.allDone { finish() } else { showFinishConfirm = true }
                }
                Button("Add exercise", systemImage: "plus") { showAddExercise = true }
                Divider()
                Button("Discard workout", systemImage: "trash", role: .destructive) { showDiscardConfirm = true }
            } label: {
                Text("Finish").bold()
            }
        }
    }

    // MARK: - Actions

    private func select(_ id: String) {
        currentID = id
        let p = logic.prefill(id, unit: unit)
        weightText = WeightUnit.number(p.weight)
        repsText = String(p.reps)
        field = .weight
        fresh = true
    }

    private func logSet() {
        guard let exercise, let reps = Int(repsText), reps > 0 else { return }
        let weight = Double(weightText) ?? 0
        let number = logic.logged(exercise.id).count + 1
        let set = ExerciseSet(exerciseID: exercise.id, setNumber: number, weightKg: unit.toKg(weight), reps: reps)
        context.insert(set)
        set.session = session
        try? context.save()

        let records = PRService.newRecords(for: set, previous: PRService.sets(for: exercise.id, in: context))
        if !records.isEmpty {
            let what = records.contains(.estimated1RM)
                ? "New PR! Estimated 1RM \(unit.format(kg: set.estimatedOneRepMaxKg))"
                : "New PR! Heaviest \(exercise.name): \(unit.format(kg: set.weightKg))"
            withAnimation(.spring) { prMessage = what }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            withAnimation { prMessage = nil }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        advance(from: exercise.id, keepValues: true)
    }

    private func skipSet() {
        guard let exercise else { return }
        let number = logic.logged(exercise.id).count + 1
        let set = ExerciseSet(exerciseID: exercise.id, setNumber: number, weightKg: 0, reps: 0, skipped: true)
        context.insert(set)
        set.session = session
        try? context.save()
        advance(from: exercise.id, keepValues: true, startRest: false)
    }

    private func advance(from id: String, keepValues: Bool, startRest: Bool = true) {
        let next = logic.nextExercise(after: id)
        if startRest {
            restEndsAt = Date.now.addingTimeInterval(TimeInterval(restSeconds))
            rescheduleRestNotification(next: next)
        }
        if let next, next != id {
            select(next)
        } else if keepValues {
            fresh = true
            field = .weight
        }
    }

    private func rescheduleRestNotification(next: String? = nil) {
        guard let end = restEndsAt else { return }
        let label = next.map { "Next: \(ExerciseCatalog.name($0))" } ?? "Next set is ready."
        CheckInScheduler.scheduleRestTimer(seconds: max(1, Int(end.timeIntervalSinceNow)), nextLabel: label)
    }

    private func finish() {
        CheckInScheduler.cancelRestTimer()
        session.endedAt = .now
        // Drop exercises that were added but never touched.
        session.exerciseOrder = session.exerciseOrder.filter { !logic.logged($0).isEmpty || logic.planned($0) != nil }
        try? context.save()
        let s = session
        Task {
            let ok = await HealthKitManager.shared.saveWorkout(start: s.startedAt, end: s.endedAt ?? .now, title: s.templateName, totalVolumeKg: s.totalVolumeKg)
            if ok { s.savedToHealth = true; try? context.save() }
        }
        showSummary = true
    }

    private func discard() {
        CheckInScheduler.cancelRestTimer()
        let s = session
        router.activeSession = nil
        // Delete after the screen has gone so nothing renders a deleted object.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            context.delete(s)
            try? context.save()
        }
    }
}

// MARK: - Edit a logged set

struct EditSetSheet: View {
    @Bindable var set: ExerciseSet
    let unit: WeightUnit
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var weight: Double = 0
    @State private var reps: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Set \(set.setNumber) · \(ExerciseCatalog.name(set.exerciseID))") {
                    Stepper(value: $weight, in: 0...2000, step: unit == .kg ? 2.5 : 5) {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("0", value: $weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text(unit.rawValue).foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $reps, in: 0...200) {
                        HStack {
                            Text("Reps")
                            Spacer()
                            Text("\(reps)").monospacedDigit()
                        }
                    }
                    if set.skipped {
                        Text("This set was skipped. Saving with reps marks it done.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Delete set", role: .destructive) {
                        let session = set.session
                        let exID = set.exerciseID
                        let deletedID = set.id
                        dismiss()
                        context.delete(set)
                        // Renumber the remaining sets for this exercise.
                        if let session {
                            for (i, s) in session.sets(for: exID).filter({ $0.id != deletedID }).enumerated() { s.setNumber = i + 1 }
                        }
                        onSave()
                    }
                }
            }
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        set.weightKg = unit.toKg(weight)
                        set.reps = reps
                        set.skipped = reps == 0
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                weight = (unit.fromKg(set.weightKg) * 10).rounded() / 10
                reps = set.reps
            }
        }
    }
}
