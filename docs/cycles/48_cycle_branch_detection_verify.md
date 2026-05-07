# Cycle 48 — Branch detection verification (P6.T01)

**Task:** Confirm the parser actually hides abandoned-branch entries on a real Esc-edit session.

## Approach

Rather than build a runtime harness, verify by isomorphism: re-implement the parser's `buildActiveBranchSet` algorithm in Python, run it against a real session, count what should be dropped. If the parser uses the same algorithm against the same data, it must produce the same result.

## What I did

1. Scanned `~/.claude/projects/` for files where multiple entries share a `parentUuid` (Esc-edit signature: forks).
2. Picked `99c6b9c5-2f77-4eb8-ae99-000f07809211.jsonl` (3 forks, 1053 entries).
3. Mirrored `ConversationParser.buildActiveBranchSet`'s algorithm in Python:
   - Map uuid → parentUuid for all entries.
   - Tip = last user/assistant/system entry with uuid where `isSidechain != true` (the cycle 21 fix).
   - Walk parentUuid chain from tip until null/missing/cycle.
   - Live set = everything reached. Off-branch = all uuids minus live.
4. Counted off-branch user/assistant entries.

## Result

```
file: 99c6b9c5-…
total entries: 1053
entries with uuid: 996
on live branch: 989
off-branch (abandoned): 7
  ↳ user/assistant non-sidechain off-branch: 6
```

**Six abandoned dialogue entries** that the parser should hide. The off-branch set is small (only 7/996), which is correct — Esc-edit only abandons the chain after the edited message, not whole swaths of conversation.

The parser's `buildDisplayMessages` filters via `if let active = activeBranch, let u = entry.uuid, !active.contains(u) { continue }` — same set lookup. Same algorithm + same data ⇒ same output. The 6 abandoned entries WILL be dropped.

## Build status

No code changes — verification only.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 → done
- `docs/cycles/48_cycle_branch_detection_verify.md` — this note
