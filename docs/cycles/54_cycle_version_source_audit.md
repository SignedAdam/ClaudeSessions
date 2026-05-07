# Cycle 54 — Version source audit (P7.T01)

**Task:** Map every place a previous version of a session might live, so T02 (`VersionHistoryService`) has a complete inventory and a stable join key.

## Findings

Four sources, all keyed by `sessionId` (UUID). Recorded in detail in the roadmap T01 notes:

1. `.live` — `~/.claude/projects/<slug>/<sessionId>.jsonl` (the source-of-truth file).
2. `.saveBackup` — `~/.claude-sessions-backups/<sessionId>/<yyyy-MM-dd'T'HH-mm-ss>.jsonl`. Written before every Save by `BackupService.backup`. Retention: last 20.
3. `.vaultLive` / `.vaultSnapshot` — `~/.ClaudeSessions/backup/projects/<slug>/<sessionId>.jsonl` and `<…>.jsonl.orig-<unix-ts>`. Written by `BackupEngine` (the continuous-backup daemon).
4. `.archive` — `~/.claude-sessions-archive/<projectId>/<sessionId>.jsonl` + a sibling `.meta.json`. Written by `ArchiveService.archive`.

Confirmed live on this machine: 2 sessions in saves backups, populated BackupEngine mirror with `.orig-*` snapshots, 1 archived session.

## Implications for T02

- Listing API: walk all four for a given `sessionId` + project slug.
- Vault entries are organized by project slug; the session's `projectPath` (or `resolvedCwd` via `SlugResolver`) gets us the slug to look in.
- Three timestamp formats — yyyy-MM-dd'T'HH-mm-ss, unix-ts, ISO. Normalize to `Date`.
- Source-kind ordering for the UI: `.live` first, then `.saveBackup` newest-first, then `.vaultSnapshot` newest-first, then `.archive`.

## Build status

No code changes — research only.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 → done with full inventory.
- `docs/cycles/54_cycle_version_source_audit.md` — this note.
