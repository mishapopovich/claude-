import SwiftUI

/// Weight + reps entry built for one sweaty thumb: two big value tiles with -/+ buttons and a
/// large number pad. Tapping a tile selects it; the first key press replaces the value.
struct SetEntryPad: View {
    enum Field { case weight, reps }

    @Binding var weightText: String
    @Binding var repsText: String
    @Binding var field: Field
    @Binding var fresh: Bool
    let unit: WeightUnit
    let weightStep: Double
    let isBodyweight: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                tile(title: isBodyweight ? "Added \(unit.rawValue)" : unit.rawValue.uppercased(), text: weightText, selected: field == .weight,
                     minus: { bumpWeight(-weightStep) }, plus: { bumpWeight(weightStep) }) {
                    field = .weight; fresh = true
                }
                tile(title: "REPS", text: repsText, selected: field == .reps,
                     minus: { bumpReps(-1) }, plus: { bumpReps(1) }) {
                    field = .reps; fresh = true
                }
            }
            keypad
        }
    }

    private func tile(title: String, text: String, selected: Bool, minus: @escaping () -> Void, plus: @escaping () -> Void, select: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                stepButton("minus", action: minus)
                Button(action: select) {
                    Text(text.isEmpty ? "0" : text)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(text)")
                .accessibilityHint("Tap to type a new value")
                stepButton("plus", action: plus)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 44, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var keypad: some View {
        let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
        return VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left")
                                } else {
                                    Text(key)
                                }
                            }
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(key == "." && field == .reps)
                        .opacity(key == "." && field == .reps ? 0.3 : 1)
                        .accessibilityLabel(key == "⌫" ? "Delete" : key)
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        var text = field == .weight ? weightText : repsText
        if key == "⌫" {
            if fresh { text = "" } else if !text.isEmpty { text.removeLast() }
        } else {
            if fresh { text = "" }
            if key == "." {
                if text.contains(".") { return }
                if text.isEmpty { text = "0" }
            }
            if text == "0" && key != "." { text = "" }
            let limit = field == .weight ? 6 : 3
            guard text.count < limit else { return }
            text += key
        }
        fresh = false
        if field == .weight { weightText = text } else { repsText = text }
    }

    private func bumpWeight(_ delta: Double) {
        let v = max(0, (Double(weightText) ?? 0) + delta)
        weightText = WeightUnit.number(v)
        fresh = true
    }

    private func bumpReps(_ delta: Int) {
        let v = max(0, (Int(repsText) ?? 0) + delta)
        repsText = String(v)
        fresh = true
    }
}
