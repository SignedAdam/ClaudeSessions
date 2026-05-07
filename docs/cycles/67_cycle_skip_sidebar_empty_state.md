# Cycle 67 — P9.T03 skipped: sidebar Favorites empty state

**Decision-only cycle.** No code change.

## Question

When the user has 0 favorites, the sidebar's Favorites section is hidden. Should we add a hint/tip somewhere so they know stars exist?

## Decision: skip

Three independent paths already teach the user about stars:

1. **Per-row star button on hover** — every `SessionRow` shows a star button when hovered. That's the natural affordance: see something useful, click the star, it now appears in your favorites. This is how every list-with-favorites UI on the platform works (Mail, Finder tags, Music). Users don't need a tutorial.
2. **Dashboard Starred section (cycle 66)** — the moment a user has *any* stars, the dashboard renders a dedicated Starred section above Recent. So discovery scales with use.
3. **Sidebar Favorites appears immediately** — count > 0 → section renders. Empty → hidden. This is the right default; an empty section with placeholder text would be visual clutter on every session of a fresh install.

Adding a "Tip: click the ★ to favorite a conversation" line in the sidebar would clutter the empty state for the 100% of sessions where the user is *not* trying to learn this feature. It's a one-time discovery problem already handled by the row affordance.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — P9.T03 → skipped (with rationale).
- `docs/cycles/67_cycle_skip_sidebar_empty_state.md` — this note.
