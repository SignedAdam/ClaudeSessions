# Cycle 50 — Settings gear verification (P6.T03)

**Task:** Confirm clicking the gear actually opens Settings reliably.

## What I found

`grep` for `showSettingsWindow|showPreferencesWindow|openSettings` across the codebase. Two call sites:

- `Views/BottomBarView.swift` — uses `@Environment(\.openSettings)` and calls `openSettingsAction()`. Correct since cycle 17.
- `Views/Toolbar/ConversationToolbar.swift` — **still using the old `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` path.** The "Change default in Settings…" item in the Extract menu fires this. Same broken path the user complained about earlier in the conversation.

## Fix

Adopted `@Environment(\.openSettings)` on `ConversationToolbar` and replaced the `NSApp.sendAction` call with `openSettingsAction()`. Now all open-settings call sites are unified on the canonical SwiftUI 14+ environment action — works reliably from cold start, no responder-chain dependencies.

Verified `grep` for `showSettingsWindow` returns only a comment in BottomBarView (documenting the older path), no remaining call sites.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Toolbar/ConversationToolbar.swift` (+@Environment, -sendAction)
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
