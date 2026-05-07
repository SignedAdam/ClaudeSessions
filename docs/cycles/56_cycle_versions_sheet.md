# Cycle 56 — Versions sheet UI (P7.T03)

**Task:** Modal listing every version of a session, with multi-select for diff.

## What I built

`Sources/ClaudeSessions/Views/VersionsView.swift` — ~210 lines, no external deps.

- 720×540 sheet, themed.
- Header: clock icon + "Versions of <title>" + one-paragraph explainer covering the four sources.
- Loads versions async via `Task.detached(priority: .userInitiated)` calling `VersionHistoryService.versions(forSessionId:projectSlug:)`. Spinner during load; empty state when no versions exist.
- Each row: kind chip (color-coded), timestamp (medium time + short date), file basename in monospaced gray, size on the right.
- Color scheme for chips: live=accent, saveBackup=success (green), vault*=human (cool blue), archive=warn (orange).
- Selection model:
  - Plain click → replace selection (1 row).
  - ⌘-click → toggle row, capped at 2 selections.
  - Selection feedback via accent-tinted background + border.
- Footer:
  - Adaptive hint text reflecting selection count.
  - "Reveal in Finder" — disabled if no selection.
  - "Diff" — enabled only at exactly 2 selected. Currently shows toast pointing to T04.
  - "Restore as new…" — enabled only at exactly 1 selected. Toast points to T05.

## What's deferred

- **Diff renderer** — T04. Button is wired but stubbed.
- **Restore-as-new-session** — T05. Same.
- **Entry points** — T06. The sheet exists but isn't yet reachable from a session row or the header. Caller pattern (matching Archive / BackupVault) is straightforward; T06 lands the wiring.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Views/VersionsView.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
