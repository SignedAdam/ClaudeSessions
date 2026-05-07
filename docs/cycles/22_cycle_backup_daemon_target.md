# Cycle 22 — Backup daemon target (P1.T02)

**Task:** Package `BackupEngine` as a standalone binary so it can run under
launchd as a LaunchAgent even when the main app is closed.

## What I did

- Moved `Sources/ClaudeSessions/Services/ContinuousBackup/{BackupEngine,BackupManifest,DirectoryTreeWatcher}.swift` to `Sources/ContinuousBackup/`.
- Marked `BackupEngine`'s public surface `public` (class, init, start, stop, the @Published vars BackupSettingsView reads, the static URLs).
- Replaced one cross-target reference: `BackupEngine`'s logger used `ISO8601DateFormatter.withFractionalSeconds` from a `SessionCreator.swift` extension in the app target. Inlined a private static formatter inside `BackupEngine` so the module is self-contained.
- Restructured `Package.swift` from one target to three:
  - `ContinuousBackup` (library)
  - `ClaudeSessions` (executable, depends on ContinuousBackup)
  - `ClaudeSessionsBackupAgent` (executable, depends on ContinuousBackup)
- Added `import ContinuousBackup` to `AppState.swift` and `BackupSettingsView.swift`.
- Wrote `Sources/ClaudeSessionsBackupAgent/main.swift`: ~50 lines. Spins up the engine, traps SIGINT/SIGTERM for clean shutdown, logs heartbeats every 5 minutes to `~/.ClaudeSessions/logs/agent.log`, hands control to `RunLoop.main.run()`.

## Verification

- `swift build` clean.
- Both binaries exist at `.build/debug/`: ClaudeSessions (10MB), ClaudeSessionsBackupAgent (428KB).
- Ran daemon for 3s with timeout: confirmed startup log lines, engine started, SIGTERM handler fires, exits 0.

## What's deferred

- T03 (LaunchAgent installer) hooks this binary into `~/Library/LaunchAgents/` so it auto-runs at login. That's the next task.
- The daemon currently writes to two log destinations (the engine's own `~/.ClaudeSessions/sync.log` and the daemon's `~/.ClaudeSessions/logs/agent.log`). This is fine — different concerns. The agent log is the heartbeat / lifecycle; the sync log is the per-file copy detail.

## Files changed

- Moved: `Sources/ClaudeSessions/Services/ContinuousBackup/*.swift` → `Sources/ContinuousBackup/*.swift`
- Edited: `Sources/ContinuousBackup/BackupEngine.swift` (public annotations, inline formatter)
- New: `Sources/ClaudeSessionsBackupAgent/main.swift`
- Edited: `Package.swift` (three targets)
- Edited: `Sources/ClaudeSessions/AppState.swift` (import)
- Edited: `Sources/ClaudeSessions/Views/Settings/BackupSettingsView.swift` (import)
- `docs/STAGE_2_ROADMAP.md` (T02 → done)
