# Cycle 44 — Settings spacing/section-header pass (P4.T05) — Phase 4 complete

**Task:** Make all seven settings tabs use the same section-header component and consistent spacing.

## What I did

- **ExtractSettingsView**: rewrote to ScrollView + VStack + `SettingsSectionHeader`. Subtitle now lives on the section header instead of a separate paragraph. The trailing `Spacer()` (a holdover from fixed-height layout) is gone since the ScrollView handles overflow naturally.
- **ClaudeCodeSettingsView**: its private `sectionHeader(_:_:)` helper now just delegates to `SettingsSectionHeader`. Existing call sites unchanged. Two-line shim — keeps the rest of the file calm but unifies the rendered look.
- **MCPSettingsView**: replaced three inline `Text("…").font(.semibold)` + caption pairs with `SettingsSectionHeader` (Port, Connect from Claude Code, Exposed tools). Theme-aware monospaced text now uses `Theme.textSecondary` instead of `.secondary`.

## What I deliberately left alone

- **Backup's 14pt page header** — that's the *page title* (with the timemachine icon), not a section header. Intentionally larger than section headers within the page. Claude Code and MCP have the same 14pt page-title pattern.
- **Backup's stat rows / location row / footer** — already in a coherent layout. No structural shuffle needed.
- **Settings tab labels in TabView** — system-managed.

## Phase 4 status

All five tasks done:

- T01 ✅ audit
- T02 ✅ ScrollViews on overflowing tabs
- T03 ✅ re-style General/AISearch/Advanced from Form to themed VStack
- T04 ✅ flexible window frame (520→640→900 × 420→520→900)
- **T05 ✅ section header + spacing unification**

The settings panel now feels like the rest of the app: same color palette, same section-header component, same VStack rhythm, ScrollView when needed. No more native-Form panel look. The user's complaint that "settings doesn't fit and looks unstyled" should be resolved.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Settings/SettingsView.swift` (Extract converted)
- Edit: `Sources/ClaudeSessions/Views/Settings/ClaudeCodeSettingsView.swift` (sectionHeader delegation)
- Edit: `Sources/ClaudeSessions/Views/Settings/MCPSettingsView.swift` (SettingsSectionHeader adoption)
- Edit: `docs/STAGE_2_ROADMAP.md` — T05 → done, **Phase 4 complete**.
