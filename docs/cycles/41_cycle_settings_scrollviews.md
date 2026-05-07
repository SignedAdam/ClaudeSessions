# Cycle 41 — Settings ScrollViews (P4.T02)

**Task:** Wrap settings tabs in `ScrollView` so content always fits.

## What I did

- `BackupSettingsView` body: wrapped its `VStack` in `ScrollView`. Removed the `Spacer()` (was meaningful for filling the old fixed-height container; redundant with scroll). Added `.frame(maxWidth: .infinity, alignment: .leading)` so the inner content stretches across the available width.
- `ClaudeCodeSettingsView` body: same pattern.

## What I deliberately didn't do

- General / Extract / AI Search / Advanced — these use `Form`. `Form` on macOS already provides scroll behavior when content exceeds the container, and per the cycle 40 audit, they fit at the default 520×420 size anyway. Wrapping them in `ScrollView` would add a redundant scroll container. Pragmatic > consistent for its own sake.
- MCP — already wrapped in cycle 39.

## Result

The two confirmed-overflow tabs (Backup, Claude Code) now scroll. Everything reachable.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Settings/BackupSettingsView.swift`
- Edit: `Sources/ClaudeSessions/Views/Settings/ClaudeCodeSettingsView.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T02 → done
