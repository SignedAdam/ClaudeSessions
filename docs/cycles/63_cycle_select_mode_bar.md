# Cycle 63 — SelectModeBar (P8.T04)

**Task:** Slim header strip atop ConversationView when select mode is active, showing the count and the available actions.

## What I built

### `Views/Conversation/SelectModeBar.swift`

- Leading: checkmark.circle icon + monospaced "N selected" count (live from `appState.selectedMessageIds.count`).
- Trailing buttons:
  - **Select all visible** — `appState.selectAllVisible()`. Bordered.
  - **Copy** — `appState.copySelection()`. Borderedprominent. ⌘C keyboard shortcut. Disabled when selection is empty.
  - **Cancel** — `appState.exitSelectMode()`. Bordered. Esc keyboard shortcut.
- `Theme.surface` bg, `Theme.accent` border-bottom (1pt, 0.4 opacity).

### `ConversationContainerView` wiring

Inserted `SelectModeBar()` between the toolbar and the content area, gated on `appState.isSelectMode`. Also gated the composer on `!appState.isSelectMode` so it doesn't compete for screen space — once you're picking messages to copy, you're done with the composer.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Views/Conversation/SelectModeBar.swift`
- Edit: `Sources/ClaudeSessions/Views/Conversation/ConversationContainerView.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
