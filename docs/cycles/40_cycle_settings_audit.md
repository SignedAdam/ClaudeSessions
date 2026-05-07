# Cycle 40 — Settings overflow audit (P4.T01)

**Task:** Map every settings tab against the current 520×420 window — find every overflow case so T02–T05 can fix them with confidence.

## Method

- Read each tab's source file (`GeneralSettingsView`, `ExtractSettingsView`, `BackupSettingsView`, `ClaudeCodeSettingsView`, `MCPSettingsView`, `AISearchSettingsView`, `AdvancedSettingsView`).
- Estimated each section's vertical footprint based on its controls (text rows, toggles, radio options, captions).
- Computed usable area: 420 - macOS tab bar (~30pt) - inner `.padding()` (~32pt) ≈ **358pt vertical**.
- Anything where the sum-of-sections exceeds ~358pt overflows at default size.

## Findings (recorded in roadmap T01 notes)

Two tabs definitively overflow at default size:
- **Backup** — the "How it works" footer falls below the fold; conditional rows (bootstrap progress, low-disk warning) eat further space.
- **Claude Code** — five sections with captions add up to ~440pt; the "Raw access" section is below the fold.

Two are fine:
- **MCP** — already wrapped in `ScrollView` from cycle 39.
- **General**, **Extract**, **AI Search**, **Advanced** — fit comfortably.

Inconsistent layout patterns across tabs (`Form` + `Section` vs raw `VStack` + `Divider` vs `VStack` + `spacing` only) — T05 should pick one.

## Implications for T02–T05

- T02: wrap every tab in `ScrollView { ... }`. Trivial, harmless on small tabs, fixes both overflowing tabs immediately.
- T03: re-style to match app theming (Theme.surface backgrounds, Theme.text headings, Theme.textSecondary body).
- T04: bump default to 640×520 so the unscrolled state is comfortable on Claude Code; min size can still allow shrink because of T02.
- T05: pick the VStack + Divider + sectionHeader() pattern (used by Claude Code and MCP) as the canonical pattern; convert Backup and General over.

## Build status

No code changes — research only.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 → done with full findings.
- `docs/cycles/40_cycle_settings_audit.md` — this note.
