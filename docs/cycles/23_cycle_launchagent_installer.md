# Cycle 23 — LaunchAgent installer (P1.T03)

**Task:** Install / uninstall / inspect the backup daemon as a macOS LaunchAgent so it runs at login and is restarted by launchd if it crashes.

## What I did

Wrote `Sources/ClaudeSessions/Services/LaunchAgentInstaller.swift`. Pure Foundation. ~190 lines including doc comments. API surface:

- `LaunchAgentInstaller.install()` — copies the daemon to `~/.ClaudeSessions/bin/ClaudeSessionsBackupAgent`, writes the plist to `~/Library/LaunchAgents/com.claudesessions.backup.plist`, runs `launchctl bootstrap gui/$UID <plist>` (with `bootout` first to clear any stale prior load). Falls back to legacy `launchctl load -w` if bootstrap is unavailable.
- `LaunchAgentInstaller.uninstall()` — runs `launchctl bootout` + legacy `unload`, deletes the plist. Leaves the binary copy in place.
- `LaunchAgentInstaller.isInstalled() -> Bool` — does the plist exist?
- `LaunchAgentInstaller.isRunning() -> Bool` — does `launchctl list <label>` exit 0?

Plist contents:

- `Label = com.claudesessions.backup`
- `ProgramArguments = [<installed-binary>]`
- `RunAtLoad = true`
- `KeepAlive = true`
- `ProcessType = Background` (lower priority, less aggressive throttling)
- `StandardOutPath` / `StandardErrorPath` → `~/.ClaudeSessions/logs/agent.{out,err}`
- `WorkingDirectory` set so relative-path file ops in the daemon are predictable
- `EnvironmentVariables.HOME` explicitly set so the daemon's home detection never depends on launchd inheritance quirks

## Design notes

**Why copy the binary?** In dev mode the daemon lives at `.build/debug/ClaudeSessionsBackupAgent`. Pointing the plist there would break the moment the user runs `swift package clean` or moves the project directory. Copying to `~/.ClaudeSessions/bin/` gives a stable path that survives rebuilds. On install, we always overwrite — so re-running `install()` after a fresh build refreshes the agent's binary.

**Why no @MainActor?** The installer is pure I/O around files and shell. Synchronous. Callers (the upcoming onboarding wizard) will call it from a background task to avoid blocking the UI on `launchctl`.

## Not done in this cycle

- No UI hookup. The wizard in T04 will surface install/uninstall buttons. The installer can be exercised manually from a debug menu or test runner if needed before T04.
- No special handling for sandboxed app (com.apple.security.app-sandbox). Right now the app is a SwiftPM exec and isn't sandboxed; if this app is ever notarized + sandboxed, the install path won't work without a SMAppService migration. That's a future-T-X concern.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/LaunchAgentInstaller.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
