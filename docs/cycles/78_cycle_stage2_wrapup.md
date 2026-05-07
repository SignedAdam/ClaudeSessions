# Cycle 78 — Stage 2 wrap-up

**Terminal cycle.** Every task in `STAGE_2_ROADMAP.md` is `done` or `skipped` (54 done, 2 skipped, 0 queued/in-progress/blocked). The Decomposition queue is empty. Per loop step 4: this is the final summary cycle and the loop stops scheduling.

## Phase tally

| Phase | Tasks | Outcome |
|-------|-------|---------|
| 1 — Data integrity | 6 | done |
| 2 — Conversation in app (claude-piped) | 6 | done |
| 3 — In-app MCP server | 7 | done |
| 4 — Settings UX overhaul | 5 | done |
| 5 — Configurable extract behavior | 4 | 3 done, 1 skipped |
| 6 — Verification + housekeeping | 5 | done |
| 7 — Conversation version history + diff | 6 | done |
| 8 — Multi-select copy mode | 5 | done |
| 9 — Pin/star polish + dashboard | 5 | 4 done, 1 skipped |
| 10 — Custom scan locations + subagent index | 7 | done |

## Headline shipments by phase

- **P1**: Append-only continuous backup mirror (separate `ContinuousBackup` SwiftPM target + LaunchAgent), backup vault with restore, slug resolver, hidden-items store. The "I lost a conversation" problem is solved at multiple layers.
- **P2**: Subprocess-driven `claude --resume` integration, terminal-agnostic `.command` launcher (`NSWorkspace.shared.open` routes to the user's default handler), `claude -p` piped extract.
- **P3**: Network.framework `NWListener` MCP server speaking JSON-RPC 2.0 on 127.0.0.1, with read/navigation/organize tool families. Lets a Claude Code instance drive Claude Sessions through MCP.
- **P4**: Tabbed Settings overhaul, theme picker, identity, terminal preference, visibility toggles.
- **P5**: Extract has two modes (new resumable session vs. piped fresh context); per-uuid runtime-noise stripping (`<system-reminder>`, `<local-command-caveat>`, command-stdout/stderr) is opt-out.
- **P6**: Verified branch detection by Python isomorphism on a real fork session; cleanup of legacy paths.
- **P7**: Four-source unified version history (live / saveBackup / vaultLive / vaultSnapshot / archive), per-uuid set-diff, copy-as-new restore that rewrites top-level `sessionId` and `custom-title` lines.
- **P8**: Select mode with checkboxes on rows, SelectModeBar with ⌘A/⌘C/Esc, ClipboardService formatting.
- **P9**: Dashboard Starred section, sidebar Favorites count pill, native SF-symbol bounce on star toggle.
- **P10**: Multi-root scanner — `Project.id` is now `<rootKey>:<slug>` with separate `slug` and `sourceRoot` fields; `ScanRootStore` singleton; "Locations" settings tab; sidebar root tag (only when ≥2 roots configured); cross-project `SubagentIndex` + `SubagentsView` browser sheet with persisted filter and live count badge.

## Run statistics

- **78 cycle notes** under `docs/cycles/` (cycles 1-78, plus a CURRENT.md).
- **53 commits** on `main`.
- All cycles built clean before commit.

## Skipped tasks (recorded)

- **P5.T04** — kept the legacy default extraction behavior in addition to the new mode (no migration toggle was required).
- **P9.T03** — sidebar Favorites empty-state hint. Decided: per-row star button + dashboard Starred section + auto-rendering sidebar already cover discovery; an empty-state placeholder would be visual noise.

## Architecture invariants worth preserving

- **No external runtime dependencies.** Everything is Foundation / SwiftUI / Network.framework.
- **No unit tests** by user instruction.
- **`@MainActor`-isolated stores** with explicit `nonisolated` escape hatches for off-actor pure computation (used for `ScanRootStore.rootKey`).
- **Separate SwiftPM targets**: `ClaudeSessions` (app), `ContinuousBackup` (lib shared with the daemon), `ClaudeSessionsBackupAgent` (daemon).
- **Scanner returns `[Project]` with embedded `[SessionInfo]` and nested `subagents`.** Everything downstream is pure derivation.
- **Per-cycle git discipline**: stage only files actually changed; one-line commit message; no unit tests.

## What's loaded for the next chapter

The roadmap file's Decomposition queue is empty. Future expansion happens by adding new phases at the bottom and re-arming a `/loop` invocation — the skill will pick them up exactly the same way.

## Loop termination

Per loop step 4: scheduling stops here. No `ScheduleWakeup` call this turn.

## Files changed

- `docs/cycles/78_cycle_stage2_wrapup.md` — this note.
