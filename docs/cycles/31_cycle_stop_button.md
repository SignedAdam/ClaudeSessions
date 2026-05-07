# Cycle 31 — Stop button (P2.T05)

**Task:** While a `claude -p` run is in-flight, the composer's send button becomes a Stop button that cancels the subprocess.

## What I built

`ComposerView` now branches on `appState.isComposerSending`:

- **Idle:** the submit button (`arrow.up.circle.fill`, accent color) — unchanged.
- **In-flight:** a stop button — small `stop.fill` glyph in error tint, surrounded by a spinning `ProgressView` ring at 55% opacity, framed by a thin tertiary-tint circle. Communicates "still running, click to stop" without taking more space than the original spinner.
- Click sends SIGINT, then SIGTERM after 1s grace via `appState.cancelComposer()` → `ClaudeRunner.cancel()` (already plumbed in cycle 29).
- Bound `⌘.` as the keyboard shortcut for stop, mirroring macOS conventions (NSApp uses ⌘. as default cancel in many places).

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Conversation/ComposerView.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T05 → done
