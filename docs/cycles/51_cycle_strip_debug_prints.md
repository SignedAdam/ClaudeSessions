# Cycle 51 — Strip leftover debug prints (P6.T04)

**Task:** Remove the `[Forker]` and `[ClaudeSessions]` timing prints; keep real error paths.

## What I found

- The original `[Forker]` continueFrom prints were already removed in earlier cleanup. Nothing to strip there.
- Five `print(...)` calls remained:
  - `AppState.performLoad`: read timing, parse timing, load-cancelled, load-failed.
  - `ProcessLauncher.launch`: .command script-write failure.

## What I changed

- Removed the **read timing** and **parse timing** prints — those were noise on every session load.
- Removed the **load-cancelled** print — cancellation is the expected outcome when the user clicks another session mid-load. No reason to log.
- Kept the **load-failed** print but routed through `NSLog` so it surfaces in `Console.app` for users running the shipped app (not just developers running from terminal).
- Moved the **launcher script-write failure** to `NSLog` as well, with a tagged `[ClaudeSessions]` prefix so it groups with our other logs.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/AppState.swift` (4 prints → 1 NSLog, 3 removed)
- Edit: `Sources/ClaudeSessions/Utilities/ProcessLauncher.swift` (1 print → NSLog)
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
