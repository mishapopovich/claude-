import SwiftUI

/// MP Coaching look: black-first, blue highlights. Light mode keeps the same blue.
enum Theme {
    /// Brand blue (same as the AccentColor asset).
    static let blue = Color("AccentColor")
    static let blueSoft = Color("AccentColor").opacity(0.35)
    static let blueFaint = Color("AccentColor").opacity(0.14)
    /// Neutral body colour for illustrations.
    static let figure = Color(.systemGray)
    static let figureFaint = Color(.systemGray3)
    static let card = Color(.secondarySystemGroupedBackground)
    static let good = Color.green
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let bad = Color.red
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// A rounded card used for headline numbers.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
    }
}
