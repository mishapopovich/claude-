import SwiftUI
import SwiftData

/// Score ring + level + the top reasons. Shown on Today.
struct ReadinessCard: View {
    let readiness: Readiness

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(Theme.blueFaint, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(readiness.score) / 100)
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(readiness.score)").font(.title2.bold()).monospacedDigit()
                    Text("ready").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Label(readiness.level.title, systemImage: readiness.level.symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.blue)
                Text(readiness.level.advice).font(.subheadline)
                if readiness.deloadSuggested {
                    Text("Time for a lighter deload week soon: about half the sets, same weights.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                }
                ForEach(readiness.factors.sorted { abs($0.impact) > abs($1.impact) }.prefix(2)) { f in
                    Text("\(f.impact >= 0 ? "▲" : "▼") \(f.text)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Everything the coach looks at, explained.
struct CoachInsightsView: View {
    @Environment(CoachStore.self) private var coach
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unit: WeightUnit = .lbs

    var body: some View {
        let report = coach.report
        List {
            Section {
                ReadinessCard(readiness: report.readiness)
            }

            Section {
                if report.readiness.factors.isEmpty {
                    Text("Not much data yet. Connect Apple Health (sleep, heart rate) and log a few workouts, and this gets sharper.")
                        .foregroundStyle(.secondary)
                }
                ForEach(report.readiness.factors) { f in
                    HStack {
                        Text(f.text)
                        Spacer()
                        Text(f.impact >= 0 ? "+\(f.impact)" : "\(f.impact)")
                            .monospacedDigit()
                            .foregroundStyle(f.impact >= 0 ? Theme.good : Theme.warn)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("What's affecting today")
            } footer: {
                Text("Starts at 75. Sleep, resting heart rate, shifts, how you said you feel, training load and your recent lifts move it up or down. Below 65 the app trims a set from each exercise; below 45 it suggests a light day.")
            }

            Section {
                let load = report.load
                HStack {
                    StatTile(title: "Last 7 days", value: unit.format(kg: load.acuteKg))
                    StatTile(title: "Usual week", value: load.chronicWeeklyKg > 0 ? unit.format(kg: load.chronicWeeklyKg) : "–")
                    StatTile(title: "Load ratio", value: load.ratio.map { String(format: "%.2f", $0) } ?? "–",
                             tint: (load.ratio ?? 1) > 1.3 ? Theme.warn : .primary)
                }
                .listRowBackground(Color.clear)
                Text("Hard weeks in a row: \(load.hardWeeksInARow). A lighter week every 4–8 hard weeks lets fatigue clear so you can keep progressing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Training load")
            }

            Section {
                ForEach(report.volume) { v in
                    VolumeRow(volume: v)
                }
            } header: {
                Text("Weekly sets per muscle")
            } footer: {
                Text("Hard sets in the last 7 days (main muscle counts 1, helper muscle ½). Rough guide: ~4 maintains, 8–16 grows, 20+ is a lot to recover from. Everyone's different.")
            }

            Section {
                let n = report.nutrition
                if let low = n.proteinLowG, let high = n.proteinHighG {
                    LabeledContent("Protein target", value: "\(Int(low))–\(Int(high)) g / day")
                    if let p = health.today.proteinG {
                        ProgressView(value: min(p / low, 1)) {
                            Text("Today: \(Int(p)) g").font(.caption)
                        }
                        .tint(Theme.blue)
                    }
                }
                if let m = n.maintenanceKcal {
                    LabeledContent(n.maintenanceMeasured ? "Your maintenance (measured)" : "Maintenance (rough estimate)",
                                   value: "\(Int(m.rounded(to: 50))) kcal")
                }
                if let t = n.targetKcal {
                    LabeledContent("Daily target for \(AppSettings.goal.label.lowercased())", value: "\(Int(t.rounded(to: 50))) kcal")
                }
                if let w = n.weeklyChangePercent {
                    LabeledContent("Weight trend", value: String(format: "%+.2f%% / week", w))
                }
                if let advice = n.advice {
                    Text(advice).font(.subheadline)
                }
            } header: {
                Text("Nutrition")
            } footer: {
                Text("Maintenance is measured from the food your app logs to Apple Health and your weight trend once there are 10+ logged days and a few weeks of weigh-ins. General guidance, not medical advice.")
            }
        }
        .navigationTitle("Coach insights")
        .refreshable { await coach.refresh(context: context) }
    }
}

struct VolumeRow: View {
    let volume: MuscleVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(volume.group.rawValue).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: volume.sets == volume.sets.rounded() ? "%.0f sets" : "%.1f sets", volume.sets))
                    .monospacedDigit()
                Text(volume.status).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let maxSets = MuscleVolume.high + 4
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    // Productive band
                    Capsule()
                        .fill(Theme.blueFaint)
                        .frame(width: w * (MuscleVolume.productiveHigh - MuscleVolume.productiveLow) / maxSets)
                        .offset(x: w * MuscleVolume.productiveLow / maxSets)
                    Capsule()
                        .fill(volume.sets > MuscleVolume.high ? Theme.warn : Theme.blue)
                        .frame(width: max(4, w * min(volume.sets, maxSets) / maxSets))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }
}

extension Double {
    func rounded(to step: Double) -> Double { (self / step).rounded() * step }
}
