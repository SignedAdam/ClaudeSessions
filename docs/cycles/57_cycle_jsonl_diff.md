# Cycle 57 — JSONL diff renderer (P7.T04)

**Task:** Compare two versions of a session and surface what changed.

## Approach: per-uuid set-diff

JSONL is append-only with stable uuids. The only changes between two versions are entries that were added or removed. So a diff reduces to:

- Read both files.
- Build `Set<uuid>` for each.
- Set-difference: uuids in left-not-right are removed; uuids in right-not-left are added.

No Myers, no edit-script, no whitespace heuristics. The semantics are exact for our domain.

## What I built

### `Services/VersionDiffService.swift`

- `enum Side { left, right }`
- `struct Hunk { id, side, entryType, role, preview }` — Identifiable, Hashable.
- `struct Result { leftPath, rightPath, leftCount, rightCount, commonCount, removed, added }`.
- `static func diff(left:right:) -> Result` — pure function, no UI, no actor.

The `preview` field is built from the message content (string body, first text/tool_use block in a content array, or the entry's `summary` field) — capped at 100 chars and stripped of newlines so it fits in a single row.

Lines without a uuid (summary entries, custom-title, attachment events) are skipped — they can't be reliably matched across versions, and they aren't user-visible content.

### `Views/VersionDiffView.swift`

760×560 themed sheet:

- Header: arrow icon + "Version diff" title + ordered chips ("older" → "newer") with kind labels and timestamps. Auto-orders by timestamp regardless of selection order.
- Summary bar: stat chips for older count, newer count, shared count, removed count, added count.
- Removed section (red tint) and Added section (green tint), each a list of `hunkRow`s with role badge + preview text.
- "Identical" empty state with checkmark when both sets match.
- Footer reminder explaining the per-uuid approach.

### Wiring in `VersionsView`

- Added `@State private var diffPair: (Version, Version)?`.
- The Diff button is no longer a stub — it calls `presentDiff()` which sets `diffPair`.
- `.sheet(item:)` driven via an internal `DiffPair: Identifiable` struct (concatenated paths as id).

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/VersionDiffService.swift`
- New: `Sources/ClaudeSessions/Views/VersionDiffView.swift`
- Edit: `Sources/ClaudeSessions/Views/VersionsView.swift` (Diff button wired, sheet presentation)
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
