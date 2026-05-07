# Cycle 60 — Decompose Phase 8 (multi-select copy mode)

**Task type:** decomposition only — Phases 1-7 done, queue head taken, broken into 5 concrete tasks. No code this cycle per the loop spec.

## Phase 8 expanded

Stage 1 left two scaffolding pieces in place:

- `AppState.isSelectMode: Bool`
- `AppState.selectedMessageIds: Set<String>`
- `ClipboardService.copyMessages(_:displayName:editedTexts:)` — formats a selection as the same plain-text transcript shape as the full-transcript copy

Nothing in the UI ever entered select mode or rendered checkboxes. Phase 8 fills that gap.

### Tasks

- T01: audit existing infra (research) — confirm what exists, find gaps.
- T02: AppState helpers — toggleSelection, selectAllVisible, enter/exit, copySelection.
- T03: message-row checkboxes — render in select mode on user + assistant messages, tap toggles.
- T04: SelectModeBar — slim strip showing "N selected · Copy · Cancel" at the top when active.
- T05: entry points + keyboard — toolbar button to enter, ⌘A to select-all-visible, Esc to exit, ⌘C to copy when in select mode.

5 tasks, ≤30 min each. Files involved are mostly known (`UserMessageView`, `AssistantMessageView`, `ConversationView` for the bar, `ConversationToolbar` for the entry point) so no surprises expected.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — Phase 8 inserted before the decomposition queue, P8 removed from queue.
- `docs/cycles/60_cycle_phase8_decomposition.md` — this note.
