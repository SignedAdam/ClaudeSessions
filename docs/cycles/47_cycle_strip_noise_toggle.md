# Cycle 47 — Strip-noise settings toggle (P5.T03) — Phase 5 effectively complete

**Task:** Surface the `stripRuntimeNoise` flag in Settings → Extract.

## What I built

- New `@AppStorage("extractStripRuntimeNoise")` (default true) on AppState.
- All three `cleaner.clean(...)` call sites in AppState now pass `stripRuntimeNoise: extractStripRuntimeNoise`.
- New "Cleanup" section in `ExtractSettingsView` with a `Toggle` bound to the same key:
  - Title: "Strip Claude Code runtime-noise wrappers"
  - Description: removes `<system-reminder>`, `<local-command-caveat>`, and command-stdout/stderr blocks from the cleaned dialogue.
- Default on. Turning off keeps the wrappers verbatim — useful when the user wants to see exactly what was injected during the original session.

## Phase 5 status

- T01 ✅ survey — context lives in system prompt, reframed T02–T04 to runtime-noise stripping.
- T02 ✅ implementation in CleanConversationService.
- **T03 ✅ settings toggle.**
- T04 **skipped** — no per-chunk granularity to expose since the wrappers are all functionally similar; single on/off is sufficient. Phase 5 effectively complete.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/AppState.swift` (AppStorage + 3 cleaner.clean call sites)
- Edit: `Sources/ClaudeSessions/Views/Settings/SettingsView.swift` (Toggle + Cleanup section in ExtractSettingsView)
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done, T04 → skipped, Phase 5 effectively complete.
