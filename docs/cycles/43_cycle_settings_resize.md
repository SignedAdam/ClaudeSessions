# Cycle 43 — Settings window resize (P4.T04)

**Task:** Bump the settings window's default size so the longer tabs fit unscrolled, but keep it resizable.

## What I did

Replaced the fixed `.frame(width: 520, height: 420)` with a flexible frame:

```swift
.frame(minWidth: 520, idealWidth: 640, maxWidth: 900,
       minHeight: 420, idealHeight: 520, maxHeight: 900)
```

- **idealWidth/Height = 640×520** — the new default. Big enough for Claude Code's 5 sections + footer to fit unscrolled, and gives Backup room for its "How it works" tail.
- **min = 520×420** — keeps the old size as a floor for users who like compact windows. The ScrollView from cycle 41 covers any overflow at the floor.
- **max = 900×900** — prevents stretching the settings panel to absurd dimensions if the user double-clicks the resize edge.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Settings/SettingsView.swift` (single line)
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
