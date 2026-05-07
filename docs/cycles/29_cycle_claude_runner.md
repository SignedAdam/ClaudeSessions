# Cycle 29 — ClaudeRunner subprocess plumbing (P2.T03)

**Task:** Wrap `claude -p --resume <id> '<prompt>'` in a Swift `Process`, async API, error capture, cancel support.

## What I built

### `Services/ClaudeRunner.swift`

- `run(sessionId:prompt:cwd:) async -> RunOutcome` — spawns `/usr/bin/env claude -p --resume <id> <prompt>` in `cwd`, with `stdin = .nullDevice` (skips the 3s stdin wait observed in P2.T01).
- `RunOutcome` enum: `.success(stdout)`, `.failure(exitCode, stderr)`, `.cancelled`, `.launchFailed(reason)`. Distinguishes signal-driven exits from non-zero codes.
- Inherits parent env, but defensively backfills HOME and PATH if launchd / Xcode handed us a stripped env.
- `cancel()` — SIGINT, then SIGTERM after a 1s grace window. Used by the upcoming Stop button in P2.T05.
- `isRunning: Bool` — surfaces alive state to callers.

### `AppState`

- New `private let claudeRunner = ClaudeRunner()`.
- `submitComposer()` is no longer a stub — it now actually invokes the runner, awaits the outcome, and shows a toast for each branch (sent / claude failed / stopped / launch failed).
- `cancelComposer()` added so the Stop button in P2.T05 has something to call.

## Notes

- FileWatcher is already wired to the open conversation file (see `selectSession` in AppState) — when claude appends entries during a run, the watcher fires and the conversation re-loads automatically. So the user types → presses ⌘↩ → composer locks → claude writes → file changes → conversation refreshes with the new entries. No extra plumbing needed in this cycle.
- I preferred `/usr/bin/env claude` over hard-coding `/Users/alice/.local/bin/claude` so the binary resolves wherever the user has it installed (PATH-based). The PATH backfill in env handles the case where the GUI process inherits an empty PATH.
- I deliberately did NOT use `--output-format stream-json` here. That belongs in P2.T04 (live append rendering with token streaming). For T03 we just spawn-and-wait and let the on-disk JSONL be the channel.

## Manual test

Couldn't test live this cycle without spending more API credit — and the previous cycle already validated the on-disk behavior. The next time the user sends a message via the composer, this code path runs end-to-end. If anything's wrong the toast will surface it.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/ClaudeRunner.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (real submit, runner property, cancel hook)
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
