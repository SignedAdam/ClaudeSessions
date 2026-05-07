# Cycle 64 — Select-mode entry + keyboard (P8.T05) — Phase 8 complete

**Task:** Add the toolbar button to enter select mode, plus the ⌘A keyboard shortcut.

## What I built

- `ConversationToolbar` — added a `checkmark.circle` IconButton next to the existing copy buttons. Click → `appState.enterSelectMode()`. Tooltip: "Pick specific messages · enter select mode".
- `SelectModeBar` — added `keyboardShortcut("a", modifiers: .command)` to the "Select all visible" button. ⌘C and Esc were already wired in cycle 63 to the Copy and Cancel buttons respectively.

The shortcut bindings live on the `SelectModeBar`'s buttons themselves, so they only attach when the bar is on screen — i.e. only when `isSelectMode` is true. No global shortcut interception.

## End-to-end flow

1. User clicks the checkmark.circle button in the toolbar.
2. SelectModeBar appears at the top, composer disappears.
3. Each message gets a left-edge checkbox.
4. User clicks checkboxes (or hits ⌘A to select all visible).
5. Hits ⌘C (or clicks Copy) → selection is formatted via `ClipboardService.copyMessages` and pasted; toast confirms.
6. Hits Esc (or clicks Cancel) → bar disappears, checkboxes vanish, composer comes back.

## Phase 8 status

All 5 tasks done:

- T01 ✅ audit
- T02 ✅ AppState helpers
- T03 ✅ message-row checkboxes
- T04 ✅ SelectModeBar
- T05 ✅ entry point + keyboard

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Toolbar/ConversationToolbar.swift` (entry button)
- Edit: `Sources/ClaudeSessions/Views/Conversation/SelectModeBar.swift` (⌘A binding)
- Edit: `docs/STAGE_2_ROADMAP.md` — T05 → done, Phase 8 complete
