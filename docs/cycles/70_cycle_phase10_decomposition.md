# Cycle 70 — Decompose Phase 10 (custom scan locations + subagent index)

**Decomposition-only cycle.** No code change.

## Quick infra check (informed the breakdown)

- `ProjectScanner.swift:6` is the single hardcoded `~/.claude/projects/` root. Every other reference is documentation or a sibling service computing paths from that one anchor.
- `SlugResolver` assumes one root.
- Subagents are stitched into `SessionInfo.subagents` and only render via the sidebar's indented child rows under their parent. No standalone surface.
- No global search/command bar exists — filter-on-list is the right pattern for the subagent browser.

## Phase 10 expanded

7 tasks, ≤30 min each. Two halves:

**Custom scan locations (T01-T04)**
- T01 audit (research, no code).
- T02 ScanRootStore (singleton, persistence).
- T03 Settings panel (list + add/remove).
- T04 ProjectScanner multi-root + sidebar root tags.

**Subagent index (T05-T07)**
- T05 build flat index from existing scan output.
- T06 Subagents browser view.
- T07 polish (count badge, empty state).

The split is intentional — T04 is the cutover point; through T03 the multi-root code is dormant infrastructure. T05+ is independent of T01-T04 and could be done in parallel if needed.

## Decomposition queue

Now empty — all queued phases have been decomposed.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — Phase 10 inserted before the queue, queue marked empty.
- `docs/cycles/70_cycle_phase10_decomposition.md` — this note.
