// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessions",
    platforms: [.macOS(.v14)],
    targets: [
        // Continuous backup engine, factored out so it can run inside the
        // app AND inside the headless daemon target without code duplication.
        .target(
            name: "ContinuousBackup",
            path: "Sources/ContinuousBackup"
        ),

        // The main SwiftUI app.
        .executableTarget(
            name: "ClaudeSessions",
            dependencies: ["ContinuousBackup"],
            path: "Sources/ClaudeSessions"
        ),

        // Headless backup daemon. Designed to run under launchd as a
        // LaunchAgent so backups happen even when the main app is closed.
        .executableTarget(
            name: "ClaudeSessionsBackupAgent",
            dependencies: ["ContinuousBackup"],
            path: "Sources/ClaudeSessionsBackupAgent"
        ),
    ]
)
