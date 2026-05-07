# Cycle 42 — Settings re-style (P4.T03)

**Task:** Drop the macOS `Form` look on the small tabs and bring them into the same VStack+Divider+sectionHeader pattern that Claude Code, MCP, and Backup already use. Apply Theme colors throughout.

## What I did

Three views converted: `GeneralSettingsView`, `AISearchSettingsView`, `AdvancedSettingsView`. Pattern:

1. Top-level `ScrollView { VStack(alignment: .leading, spacing: 14) { ... } .padding().frame(maxWidth: .infinity, alignment: .leading) }`.
2. Sections introduced by a shared `SettingsSectionHeader` view — title (12pt semibold, `Theme.text`) + optional subtitle (10pt, `Theme.textSecondary`). Lives in `SettingsView.swift`, available to other settings views.
3. Field rows are simple `HStack` — label in `Theme.textSecondary`, control on the right. Examples: TextField for display name + paths, Picker for theme + model.
4. Captions / footnotes use `Theme.textTertiary` to match the rest of the app.

Result: the Form-style nested labels are gone, the system white panel is gone (the TabView outer chrome stays — that's macOS, not us). Each tab now reads like the rest of the app's panels.

## Trade-offs

- TabView's tab bar at the top is system-styled; we don't try to replace it. The tab content is the part that matters; styling the chrome is a follow-up not worth pursuing without going to a full custom sidebar layout.
- Extract was already VStack-based. Skipped — no Form to remove. Matches the new pattern except for the SettingsSectionHeader; that's a T05 cosmetic.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Settings/SettingsView.swift` (3 views converted, new SettingsSectionHeader struct)
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
