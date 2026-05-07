# Cycle 53 — Decompose Phase 7 (version history + diff)

**Task type:** decomposition only — per the loop spec, when the earliest unfinished phase has no `queued` / `in-progress` tasks (Phases 1-6 all done), the next cycle takes the front of the Decomposition queue and breaks it into 4-7 concrete tasks. No code this cycle.

## Phase 7 expanded

Six tasks, each ≤30 min:

- T01: audit version sources (research) — saves backups dir, BackupEngine mirror + `.orig-*` snapshots, archive entries.
- T02: VersionHistoryService — unify the sources behind one API.
- T03: Versions sheet UI — modal with multi-select.
- T04: JSONL diff renderer — per-uuid set-diff (much simpler than line diff for our append-only format).
- T05: Restore-as-new-session — copy a version into the project as a fresh sessionId.
- T06: wire entry points — context menu + session header button.

## What I leaned on while decomposing

The existing infrastructure (cycles 03, 25, 26) means we already have the version data on disk in three places — we just don't expose them as a unified "Versions" view yet. T01 is a research cycle that establishes the inventory; T02 unifies; T03–T06 build the UX.

Per-uuid diff (T04) is a key simplification — JSONL is append-only with stable uuids, so a diff between two versions reduces to a set-difference on uuids. No need for Myers; no two entries with the same uuid will differ in content meaningfully (they'd be edits, which we already track separately).

## Files changed

- `docs/STAGE_2_ROADMAP.md` — added "## Phase 7" section with 6 tasks; removed Phase 7 from the Decomposition queue.
- `docs/cycles/53_cycle_phase7_decomposition.md` — this note.
