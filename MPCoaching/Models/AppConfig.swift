import Foundation

/// Build-time switches. Edit these when setting the app up on your Apple Developer account.
enum AppConfig {
    /// CloudKit container for friends and leaderboards, e.g. "iCloud.com.yourname.mpcoaching".
    ///
    /// Leave nil to build without iCloud (works with a free Apple ID; the Leaderboard tab then
    /// explains how to turn it on). To enable: Xcode → target → Signing & Capabilities →
    /// + Capability → iCloud → tick CloudKit → add a container, then paste its id here.
    static let cloudKitContainerID: String? = nil
}
