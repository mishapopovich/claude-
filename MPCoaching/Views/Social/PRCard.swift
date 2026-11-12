import SwiftUI

/// Branded square image for sharing a PR or total to Instagram, Messages, etc.
/// Every shared card carries the app name: free marketing.
struct PRCardView: View {
    let title: String
    let value: String
    let detail: String
    let name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.02, green: 0.08, blue: 0.22)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("MP COACHING").kerning(3)
                }
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.blue)
                Spacer()
                Text(title.uppercased())
                    .font(.system(size: 34, weight: .bold))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(value)
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack {
                    Text(name).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Capsule().fill(Theme.blue).frame(height: 8)
            }
            .padding(64)
        }
        .frame(width: 1080, height: 1080)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
enum PRCardRenderer {
    static func render(title: String, value: String, detail: String, name: String) -> Image {
        let renderer = ImageRenderer(content: PRCardView(title: title, value: value, detail: detail, name: name))
        renderer.scale = 1
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "trophy")
    }
}
