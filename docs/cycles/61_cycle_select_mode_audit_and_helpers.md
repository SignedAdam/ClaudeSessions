# Cycle 61 — Select-mode audit + AppState helpers (P8.T01 + T02)

**Two tasks in one cycle** — the audit was 5 minutes (3 grep hits, no surprises) so I rolled T02's helpers into the same cycle to keep the loop moving.

## T01 — audit

Grepped the codebase for `isSelectMode`, `selectedMessageIds`, `copyMessages`. Three sites total:

- `AppState.swift` — the two `@Published` fields (cycle 09 era).
- `ClipboardService.swift` — `static func copyMessages([DisplayMessage], displayName:, editedTexts:)`.

No view file references either. Phase 8 is pure greenfield UI on top of existing dormant scaffolding.

## T02 — AppState helpers

Five methods added to `AppState`, all under one new `// MARK: - Multi-select copy mode (Phase 8)` section near the existing composer methods:

- `enterSelectMode()` — sets flag, clears selection.
- `exitSelectMode()` — clears flag and selection. Idempotent.
- `toggleSelection(messageId:)` — set/remove on `selectedMessageIds`.
- `selectAllVisible()` — replaces selection with every currently-visible message id, **respecting the user's filter pills and reading-mode rules** (uses the same predicate as `ConversationView.filteredMessages`).
- `copySelection()` — pulls the chosen `DisplayMessage`s out of `currentConversation.displayMessages`, calls `ClipboardService.copyMessages`, fires a toast with the count.

All five are ≤15 lines. No new types — the existing `selectedMessageIds: Set<String>` is the source of truth.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/AppState.swift` (5 helper methods)
- Edit: `docs/STAGE_2_ROADMAP.md` — T01 → done with audit, T02 → done
