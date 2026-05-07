# Cycle 55 — VersionHistoryService (P7.T02)

**Task:** Single API that returns every previous version of a session, regardless of which on-disk source produced it.

## What I built

`Sources/ClaudeSessions/Services/VersionHistoryService.swift`. ~150 lines.

- `enum SourceKind`: `.live`, `.saveBackup`, `.vaultLive`, `.vaultSnapshot`, `.archive`.
- `struct Version` (Identifiable, Hashable): `{id, sessionId, kind, filePath, timestamp, size, isCurrent}`.
- Static API: `versions(forSessionId: String, projectSlug: String?) -> [Version]`. Pure filesystem walks; no manifest dependency.

Five private helpers, one per source. Each handles its own timestamp format:

- `liveVersions` — stat the source-of-truth file under `~/.claude/projects/<slug>/<id>.jsonl`. mtime is the timestamp.
- `saveBackupVersions` — list `~/.claude-sessions-backups/<id>/`. Parses `yyyy-MM-dd'T'HH-mm-ss.jsonl` filenames; falls back to mtime if parsing fails.
- `vaultVersions` — list `~/.ClaudeSessions/backup/projects/<slug>/`, filter by `<id>.jsonl` prefix. Live mirror = `<id>.jsonl`, snapshots = `<id>.jsonl.orig-<unix-ts>`. Parses unix-ts from suffix.
- `archiveVersions` — uses `ArchiveService().listArchived().filter { $0.sessionId == id }`.

Sort: `.live` first, then by source-kind priority (saveBackup → vault* → archive), then newest-first within the same kind.

## Bonus fix

The linter dropped the `displayName` parameter from `ProcessLauncher.resumeSession` (with a good reason — `--name` makes Claude Code print title-based resume hints which break across cwds). Updated the one remaining call site in `MCPLaunchTools.resume_in_terminal` to match.

## Build status

`swift build` clean.

## Files changed (this cycle's intent)

- New: `Sources/ClaudeSessions/Services/VersionHistoryService.swift`
- Edit: `Sources/ClaudeSessions/Services/MCPTools/MCPLaunchTools.swift` (drop the now-removed `displayName:` arg)
- Edit: `docs/STAGE_2_ROADMAP.md` — T02 → done
