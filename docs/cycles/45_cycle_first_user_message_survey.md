# Cycle 45 — First-user-message survey (P5.T01)

**Task:** Map what Claude Code actually puts in the first user entry of a session, so the "preserve initial context" toggle in T02–T04 has a real target.

## What I did

Sampled ~40 random `.jsonl` files across `~/.claude/projects/`. For each, walked through user-type entries and inspected the first one (sometimes a few). Looked specifically for CLAUDE.md text, git status snippets, tool definitions, system reminders.

## Findings

**Result inverted my expectation.** The "injected context" the user was worried about (CLAUDE.md, git, tools list) is in Claude Code's **system prompt**, not in any JSONL entry — confirmed by the docs research from cycle 21. The first user entry is almost always just the user's prompt text.

Catalogued five flavors of content that DO appear in user entries:

1. Plain prompt text (most common, ~95% of first entries).
2. `<command-message>` / `<command-name>` / `<command-args>` — slash command invocations. User intent; should be preserved.
3. `<local-command-caveat>` — Claude Code boilerplate; should be strippable.
4. `<system-reminder>` — runtime nudges; should be strippable.
5. Tool-result blocks (when `content` is a list) — never first-message; already handled by our parser as a separate display type.

## Plan revision

T02–T04 reframed in the roadmap: the original "preserve initial context" toggle was solving a non-problem. The actual user-facing control is "Strip Claude Code's runtime noise from extracted dialogue" (default on). T02 implements the strip in `CleanConversationService`, T03 surfaces the toggle in Settings → Extract, T04 (stretch) allows per-wrapper override.

## Build status

No code changes — research only.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 → done, T02–T04 reframed in T01 notes.
- `docs/cycles/45_cycle_first_user_message_survey.md` — this note.
