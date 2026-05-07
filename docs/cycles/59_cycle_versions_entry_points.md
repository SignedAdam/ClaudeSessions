# Cycle 59 — Versions sheet entry points (P7.T06) — Phase 7 complete

**Task:** Wire the Versions sheet into the UI. After this cycle, the user can actually reach version history without writing test code.

## What I built

### `AppState`

- `VersionsContext: Identifiable` struct — sessionId, sessionTitle, projectSlug, projectCwd. Used as the `.sheet(item:)` driver.
- `@Published var versionsContext: VersionsContext?`
- `presentVersions(for: SessionInfo)` — derives slug from filePath's parent dir, resolves cwd via `SlugResolver.bestCwd(slug:recorded:)`, populates the context.

### `ContentView`

New `.sheet(item: $appState.versionsContext) { ctx in VersionsView(...) }` block alongside the existing Archive / Backup Vault sheets.

### Session row context menu

Added "Versions…" item between "Hide/Unhide" and "Archive". Plumbed via a new `onShowVersions: () -> Void` closure on `SessionRow`, then `(SessionInfo) -> Void` on `FavoritesSection` and `ProjectSection`, terminating at `appState.presentVersions(for:)` in the parent (called both for top-level sessions and for subagent rows).

### Session header

Added a `clock.arrow.circlepath` icon button in the right-side cluster (between the modified-date timestamp and the close button). Click → `appState.presentVersions(for: sessionInfo)`. Tooltip: "Versions · browse, diff, and restore previous on-disk versions of this session".

## Phase 7 status

All six tasks done:

- T01 ✅ audit version sources (4 sources, all keyed by sessionId)
- T02 ✅ VersionHistoryService — unified API
- T03 ✅ VersionsView — multi-select sheet
- T04 ✅ per-uuid set-diff (VersionDiffService + VersionDiffView)
- T05 ✅ VersionRestoreService — restore-as-new-session
- **T06 ✅ entry points wired (context menu + header button)**

The user can now: right-click any session → Versions… → see live + saved + vault + archive copies → optionally ⌘-click two of them → Diff to see what's added/removed → or Restore-as-new to copy any version into the project as a fresh session.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/AppState.swift` (VersionsContext + presentVersions)
- Edit: `Sources/ClaudeSessions/ContentView.swift` (sheet wiring)
- Edit: `Sources/ClaudeSessions/Views/Sidebar/SessionRow.swift` (onShowVersions closure + menu item)
- Edit: `Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift` (closure plumbing through FavoritesSection + ProjectSection, both top-level and subagent SessionRow callers)
- Edit: `Sources/ClaudeSessions/Views/Conversation/SessionHeaderView.swift` (Versions button)
- Edit: `docs/STAGE_2_ROADMAP.md` — T06 → done, **Phase 7 complete**
