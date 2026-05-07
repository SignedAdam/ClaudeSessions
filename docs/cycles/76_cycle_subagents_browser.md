# Cycle 76 — Subagents browser view (P10.T06)

**The headline subagent surface.** Until now subagent runs were hidden behind a parent-row chevron in the sidebar. Now they're directly browseable across every project and root.

## Sheet, not page

Modeled on `ArchiveView`: a 640×560 sheet with header, search bar, list, empty state. No new top-level navigation needed; the existing in-app nav stays the conversation pane. Trigger via `appState.showSubagentsSheet`, set by a new sparkle footer icon in the sidebar (between Archive and Backup Vault).

## Layout

```
┌──────────────────────────────────────────────┐
│ ✦ Subagents  (12)                       [×]  │
│  filter subagents…                           │
├──────────────────────────────────────────────┤
│ ✦ [code-reviewer] Review the auth migration │
│   narkis-api · auth migration plan · 2d ago │
│ ✦ [search-deep] Find all GraphQL resolvers   │
│   webapp · resolver audit · 3d ago           │
└──────────────────────────────────────────────┘
```

The agent name (when extractable from `agent-<NAME>-<uuid>.jsonl`) renders as a small toolTint pill — same visual idiom as the favorites count badge from cycle 69, so the user reads it as "category, not generic count."

## Filter

Live filter over title / parent title / project name / agent name. Lower-cased substring match. No fancy ranking — the data set is small and chronologically ordered.

## Row click

`Task { await appState.selectSession(entry.subagent) }` then `isPresented = false`. The conversation pane already handles `isSubagent: true` sessions correctly (cycle 74's selectSession audit confirmed).

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Views/SubagentsView.swift` (new).
- `Sources/ClaudeSessions/AppState.swift` — `@Published var showSubagentsSheet`.
- `Sources/ClaudeSessions/ContentView.swift` — sheet binding.
- `Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift` — sparkle footer button.
- `docs/STAGE_2_ROADMAP.md` — P10.T06 → done.
