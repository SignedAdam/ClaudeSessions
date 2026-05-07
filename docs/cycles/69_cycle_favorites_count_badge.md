# Cycle 69 — Favorites count badge (P9.T05) — Phase 9 complete

**Audit-then-refactor cycle.** The count already existed; it just looked exactly like every other project's session count, so it carried no extra meaning.

## Change

`Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift`, FavoritesSection header:

```swift
Text("\(sessions.count)")
    .font(.system(size: 9, weight: .semibold, design: .monospaced))
    .foregroundStyle(Theme.warnTint)
    .padding(.horizontal, 6).padding(.vertical, 2)
    .background(Theme.warnTint.opacity(0.14))
    .clipShape(Capsule())
```

A tiny warnTint pill — same hue as the star icon and the dashboard Starred section's accents. It reads as "you have N starred conversations" rather than "this section has N items."

## Phase 9 status

All 5 tasks resolved:

- T01 audit — done (cycle 65)
- T02 dashboard Starred section — done (cycle 66)
- T03 sidebar empty state — skipped (cycle 67, current behavior is correct)
- T04 star toggle bounce — done (cycle 68)
- T05 favorites badge — done (this cycle)

The pin/star surface is now coherent: hover-toggle on every row → bouncing toggle → sidebar pill shows the running total → dashboard pulls them all to the top.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift` — count restyled as warnTint pill.
- `docs/STAGE_2_ROADMAP.md` — P9.T05 → done.
