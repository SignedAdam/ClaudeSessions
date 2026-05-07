# Cycle 66 — Dashboard Starred section (P9.T01 + P9.T02)

**Two tasks rolled together** — T01 was a 3-grep audit confirming what cycle 65 sketched, and T02 is the headline ask from the deep-think round.

## T01 — audit (already cataloged in cycle 65)

- `FavoritesStore.shared` — UserDefaults-backed singleton, ~80 lines.
- Sidebar `FavoritesSection` renders only when non-empty (cycle ~37).
- `SessionRow`'s star button toggles via `favoritesStore.toggle(sessionId)`.
- Dashboard had no starred surface until this cycle.

## T02 — Dashboard "Starred" section

### Data

```swift
@EnvironmentObject var favoritesStore: FavoritesStore

private var starredSessions: [(session: SessionInfo, project: Project)] {
    let favs = favoritesStore.favoriteSessionIds
    guard !favs.isEmpty else { return [] }
    return allSessions
        .filter { favs.contains($0.session.id) }
        .sorted { $0.session.modified > $1.session.modified }
        .prefix(8)
        .map { $0 }
}
```

### Layout

`starredSessionsSection` mirrors `recentSessionsSection`'s structure:

- Section header: star.fill (warnTint) + "STARRED" (monospaced uppercase) + count.
- Rows: clickable, leading star icon (warnTint) + title + project · modified · message count · chevron.
- Distinguished from Recent rows via a warnTint border (0.25 opacity) so the user knows at a glance these are pinned.

Inserted between `quickActions` and `recentSessionsSection`. Rendered only when at least one session is starred (`if !starredSessions.isEmpty`).

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/HomeDashboardView.swift` (FavoritesStore env, starredSessions computed, starredSessionsSection view, body insertion)
- Edit: `docs/STAGE_2_ROADMAP.md` — T01 + T02 → done
