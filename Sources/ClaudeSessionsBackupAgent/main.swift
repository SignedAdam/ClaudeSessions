import Foundation
import ContinuousBackup

// Headless backup daemon for Claude Sessions.
//
// Mirrors `~/.claude/projects/` into `~/.ClaudeSessions/backup/projects/`
// continuously, even when the main app is closed. Designed to run under
// launchd as a `LaunchAgent` (see Phase 1 / T03 — installer).
//
// No UI. No CLI flags. Just: spin up the engine, log a heartbeat, and
// run forever. Stops cleanly on SIGINT/SIGTERM.

let logURL = BackupEngine.backupHome.appendingPathComponent("logs/agent.log")
try? FileManager.default.createDirectory(
    at: logURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }
    FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
}

log("ClaudeSessionsBackupAgent starting (pid \(getpid()))")

let engine = BackupEngine()
engine.start()

// Trap signals so launchd can ask us to exit cleanly.
signal(SIGINT) { _ in
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] received SIGINT, exiting\n"
    FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    exit(0)
}
signal(SIGTERM) { _ in
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] received SIGTERM, exiting\n"
    FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    exit(0)
}

// Heartbeat to the log every 5 minutes so a tail of `agent.log` shows the
// daemon is alive. The engine's own work happens on its internal queue.
let heartbeat = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
heartbeat.schedule(deadline: .now() + 300, repeating: 300)
heartbeat.setEventHandler {
    log("alive · tracked \(engine.trackedFiles) · backup \(engine.totalBackupBytes) bytes · last sync \(engine.lastSyncAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never")")
}
heartbeat.resume()

log("engine started — entering run loop")

// Hand control to the runloop. The engine's FSEvents stream and dispatch
// queues stay alive as long as this process is alive.
RunLoop.main.run()
