# Cycle 27 — Validate `claude -p --resume` flow (P2.T01)

**Task:** Confirm what `claude -p --resume <id> '<prompt>'` does to the JSONL on disk, so the embedded-chat plumbing in P2.T03 can be designed correctly.

## What I did

1. Read `claude --help` for relevant flags (`-p`, `-r/--resume`, `--session-id`, `--no-session-persistence`, `--output-format`, `--include-partial-messages`, `--fork-session`).
2. Picked a small live session in this project, snapshotted line/byte count + last entry uuid.
3. Ran `cd <cwd> && claude -p --resume <sessionId> 'Reply with exactly the word PONG and nothing else.'`
4. Re-snapshotted, diffed the appended entries.

## Findings (recorded in roadmap T01 notes)

- File **appends** in place with the same sessionId. Same JSONL, never a new file.
- 10 new entries per round-trip in this case (system bookkeeping + user + assistant).
- The user prompt lands as a `type: user` entry; the response as a `type: assistant`.
- Exit code 0 on success. On error (e.g. credit balance too low), non-zero with a diagnostic on stderr.
- Without `stdin < /dev/null` redirect, claude waits ~3s for stdin. Our `Process` wrapper should set `standardInput = .nullDevice` to skip that.
- `--output-format stream-json --include-partial-messages` is the path for live token streaming when we get to P2.T04.

## Build status

No code changed in this cycle — research only. No build needed.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 → done with full findings.
- `docs/cycles/27_cycle_validate_claude_p_resume.md` — this note.
