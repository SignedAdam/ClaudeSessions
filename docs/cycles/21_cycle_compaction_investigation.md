# Cycle 21 — Compaction investigation (P1.T01)

**Task:** P1.T01 — confirm what `/compact` and `claude --resume` do to JSONL files on disk.

## What I did

- Fetched Claude Code's `/compact` docs (https://code.claude.com/docs/en/context-window) — confirms compact "replaces the conversation with a structured summary" in-memory, but doesn't say what happens on disk.
- Fetched the settings reference for `cleanupPeriodDays` — confirms it's a hard unlink, default 30 days, minimum 1.
- Inspected a real compacted session file on disk:
  `~/.claude/projects/-Users-sauel-dev-AtlasNativeClaude/ebe95661-63e3-4a17-9917-db93bd8a82ad.jsonl`
- Counted lines pre/post compact-summary entry, traced parent UUIDs.

## What I learned

1. **`/compact` is append-only.** Same file, same sessionId. The compaction marker is a single synthetic user entry tagged `isCompactSummary: true` whose parentUuid links it to the last pre-compaction assistant turn, so the parent chain is intact. Old content is preserved on disk.

2. **`claude --resume <id>` appends.** Doesn't rewrite. Same file grows.

3. **`--fork-session` creates a new file.** Original untouched.

4. **The user's missing conversations are almost certainly `cleanupPeriodDays` deletion.** Hard unlink, fires when Claude Code starts. If the app isn't running, our backup engine doesn't see it before the file is gone. This is exactly what the LaunchAgent in T02/T03 is for.

## Implications

The Phase 1 plan is still right, but T05 (versioned snapshots) is simpler than feared: there's no compaction-overwrite to defend against. The real defense is just keeping the backup mirror running 24/7 (T02 + T03) and never deleting from it.

Findings written into the roadmap as a "Findings" subsection under T01 so future cycles working T05 don't re-do this research.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 marked done, findings appended.
- `docs/cycles/21_cycle_compaction_investigation.md` — this note.

## Build status

No code changes this cycle. No build needed.
