# Cycle 65 — Decompose Phase 9 (pin/star polish + dashboard pinned section)

**Task type:** decomposition only — Phases 1-8 done, queue head taken, broken into 5 concrete tasks. No code this cycle per the loop spec.

## Quick infra check (informed the breakdown)

- `FavoritesStore` (singleton, UserDefaults-backed) is solid: toggle / add / remove / isFavorite / count / prune.
- Sidebar already has a `FavoritesSection` (renders when non-empty), pulling from the store.
- HomeDashboardView has Recent / Top Projects / At-a-glance — but no Pinned section, which the user explicitly asked for in the deep-think round.

## Phase 9 expanded

5 tasks, ≤30 min each:

- T01: audit (research, confirm what I sketched here).
- T02: dashboard "Starred" section (the headline feature — reuses Recent's row pattern).
- T03: sidebar empty-state decision (likely → mark skipped if T01 confirms current behavior is fine).
- T04: star-toggle animation (small delight win).
- T05: count badge in sidebar Favorites header.

## Files involved (anticipated)

- `Views/HomeDashboardView.swift` (T02)
- `Views/Sidebar/SidebarView.swift` — `FavoritesSection` (T05)
- `Views/Sidebar/SessionRow.swift` — star button (T04)

## Files changed

- `docs/STAGE_2_ROADMAP.md` — Phase 9 inserted before the Decomposition queue, P9 removed from queue.
- `docs/cycles/65_cycle_phase9_decomposition.md` — this note.
