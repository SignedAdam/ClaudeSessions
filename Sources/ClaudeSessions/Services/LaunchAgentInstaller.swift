import Foundation

/// Installs / uninstalls / inspects the Claude Sessions backup daemon as a
/// macOS LaunchAgent. Once installed, launchd runs the daemon at user login
/// (via `RunAtLoad`) and respawns it if it crashes (via `KeepAlive`), so
/// backups continue even when the main app is closed.
///
/// Pure Foundation. No SwiftUI / no AppKit dependencies — can be exercised
/// from anywhere in the app, or from a future CLI/test harness.
///
/// ## What gets created
///
/// - `~/Library/LaunchAgents/com.claudesessions.backup.plist` — the launchd
///   spec. macOS reads this both at user login and at install time.
/// - `~/.ClaudeSessions/bin/ClaudeSessionsBackupAgent` — a copy of the
///   daemon binary at a stable location, so the plist's path doesn't break
///   when the developer cleans `.build/` or rebuilds.
/// - `~/.ClaudeSessions/logs/agent.{out,err}` — stdout/stderr captured by
///   launchd. The daemon also writes its own log to `agent.log` in that
///   directory.
enum LaunchAgentInstaller {

    static let label: String = "com.claudesessions.backup"

    static let agentPlistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }()

    static let installedBinaryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ClaudeSessions/bin/ClaudeSessionsBackupAgent")
    }()

    static let logsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ClaudeSessions/logs")
    }()

    // MARK: - Status

    /// True when the plist is on disk. Doesn't tell you whether launchd
    /// has actually loaded it — see `isRunning` for that.
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    /// True when launchd reports a running job for our label.
    static func isRunning() -> Bool {
        let out = runShell(["/bin/launchctl", "list", label])
        // launchctl list returns 0 when the job is loaded, 113 (or non-zero)
        // when it isn't. Output isn't strictly needed; rc tells us enough.
        return out.exitCode == 0
    }

    // MARK: - Installation

    enum InstallError: Error, LocalizedError {
        case daemonBinaryNotFound(String)
        case writeFailed(Error)
        case launchctlFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .daemonBinaryNotFound(let path):
                return "ClaudeSessionsBackupAgent binary not found at \(path). Build the project first (`swift build`)."
            case .writeFailed(let err):
                return "Failed to write LaunchAgent files: \(err.localizedDescription)"
            case .launchctlFailed(let rc, let stderr):
                return "launchctl exited \(rc): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }

    /// Install the launch agent: copy the daemon to a stable location,
    /// write the plist, and ask launchd to load it. Idempotent — safe to
    /// call when already installed (will refresh the binary + plist).
    static func install() throws {
        let fm = FileManager.default

        // 1. Locate the daemon binary built alongside the app.
        guard let sourceDaemon = locateDaemonBinary(), fm.fileExists(atPath: sourceDaemon.path) else {
            throw InstallError.daemonBinaryNotFound(locateDaemonBinary()?.path ?? "<not located>")
        }

        // 2. Copy daemon to a stable location.
        do {
            try fm.createDirectory(at: installedBinaryURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installedBinaryURL.path) {
                try fm.removeItem(at: installedBinaryURL)
            }
            try fm.copyItem(at: sourceDaemon, to: installedBinaryURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedBinaryURL.path)
        } catch {
            throw InstallError.writeFailed(error)
        }

        // 3. Write the plist.
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [installedBinaryURL.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": logsDir.appendingPathComponent("agent.out").path,
            "StandardErrorPath": logsDir.appendingPathComponent("agent.err").path,
            "WorkingDirectory": installedBinaryURL.deletingLastPathComponent().path,
            "EnvironmentVariables": [
                "HOME": fm.homeDirectoryForCurrentUser.path,
            ]
        ]
        do {
            try fm.createDirectory(at: agentPlistURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: agentPlistURL)
        } catch {
            throw InstallError.writeFailed(error)
        }

        // 4. Bootstrap into launchd. Best-effort unload first in case it's
        //    already loaded with a stale path; that's why we use bootout
        //    /bootstrap rather than the older load/unload.
        let uid = getuid()
        _ = runShell(["/bin/launchctl", "bootout", "gui/\(uid)/\(label)"])
        let result = runShell(["/bin/launchctl", "bootstrap", "gui/\(uid)", agentPlistURL.path])
        if result.exitCode != 0 {
            // Fall back to legacy load if bootstrap path isn't available.
            let legacy = runShell(["/bin/launchctl", "load", "-w", agentPlistURL.path])
            if legacy.exitCode != 0 {
                throw InstallError.launchctlFailed(result.exitCode, result.stderr)
            }
        }
    }

    /// Uninstall: ask launchd to forget the agent and delete the plist.
    /// The copied binary at `~/.ClaudeSessions/bin/` is left in place — if
    /// the user wants it gone, they can remove `~/.ClaudeSessions/` whole.
    static func uninstall() throws {
        let uid = getuid()
        _ = runShell(["/bin/launchctl", "bootout", "gui/\(uid)/\(label)"])
        // Legacy fallback for older macOS where bootout might fail silently.
        _ = runShell(["/bin/launchctl", "unload", agentPlistURL.path])
        if FileManager.default.fileExists(atPath: agentPlistURL.path) {
            try FileManager.default.removeItem(at: agentPlistURL)
        }
    }

    // MARK: - Daemon discovery

    /// Find the freshly-built daemon binary alongside the running executable.
    /// In `swift run` mode that's `.build/debug/`. In a shipped app the
    /// daemon lives inside `Claude Sessions.app/Contents/MacOS/` next to the
    /// main executable.
    private static func locateDaemonBinary() -> URL? {
        let fm = FileManager.default

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let sibling = executableDir.appendingPathComponent("ClaudeSessionsBackupAgent")
            if fm.fileExists(atPath: sibling.path) { return sibling }
        }

        // Development fallback for plain SwiftPM launches.
        let bundleSibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ClaudeSessionsBackupAgent")
        if fm.fileExists(atPath: bundleSibling.path) { return bundleSibling }

        return nil
    }

    // MARK: - Shell helper

    private struct ShellResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    private static func runShell(_ arguments: [String]) -> ShellResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: arguments[0])
        task.arguments = Array(arguments.dropFirst())
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: "\(error)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ShellResult(
            exitCode: task.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
