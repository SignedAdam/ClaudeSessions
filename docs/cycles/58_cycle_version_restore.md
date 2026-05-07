# Cycle 58 — Restore as new session (P7.T05)

**Task:** Pick any version → copy it back into the project as a fresh sessionId.

## What I built

### `Services/VersionRestoreService.swift`

- `restore(version:projectCwd:originalTitle:) throws -> Restored` — reads JSONL, rewrites top-level `sessionId` on every line (+ on `custom-title` entries which carry their own copy), passes the rewritten content to `SessionCreator.create(...)` which writes the file and upserts `sessions-index.json`.
- Title format: `<originalTitle> · restored from <MMM d HH:mm>`.
- Walks the rewritten JSONL once to count user/assistant entries (for the index's `messageCount`) and capture the first user prompt (for the index's `firstPrompt`).

`uuid` and `parentUuid` on individual entries are preserved — re-using uuids across the new session is fine because the new sessionId scopes them.

### `AppState.restoreVersion(...)`

Thin wrapper. On success: toast + `loadProjects()` so the new session appears in the sidebar.

### `VersionsView` wiring

- New init param `projectCwd: String?` — required for restore writes (the parent caller, T06, will pass `conv.resolvedCwd`).
- New `@State private var pendingRestore: Version?` plus a confirmation alert that explains exactly what will happen.
- Restore button now calls `stageRestore()` → alert → `performRestore()` → close the sheet on success.
- Disabled when `projectCwd == nil` (e.g. an archive entry whose original project we can't resolve).

## Build status

`swift build` clean.

## What's next

T06 — wire entry points into the sheet from session-row context menu and the conversation header. The sheet is fully functional but currently has no caller.

## Files changed

- New: `Sources/ClaudeSessions/Services/VersionRestoreService.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (restoreVersion method)
- Edit: `Sources/ClaudeSessions/Views/VersionsView.swift` (projectCwd param, alert, restore wiring)
- Edit: `docs/STAGE_2_ROADMAP.md` — T05 → done
