# Cycle 68 — Star toggle micro-interaction (P9.T04)

**Two lines.** SF Symbols ships a built-in bounce effect; reaching for hand-rolled `.scaleEffect` + `withAnimation` here would just be reinventing what the framework already does well — and on macOS 14 the symbol effect is the platform idiom.

## Change

In `Sources/ClaudeSessions/Views/Sidebar/SessionRow.swift`, on the star Image:

```swift
.symbolEffect(.bounce, value: isFavorite)
.contentTransition(.symbolEffect(.replace))
```

- `.symbolEffect(.bounce, value:)` — fires the bounce whenever `isFavorite` changes, in either direction (star OR unstar).
- `.contentTransition(.symbolEffect(.replace))` — when the systemName flips between `star` and `star.fill`, SF Symbols crossfades the two glyphs instead of cutting.

No `@State`, no counter, no animation curves to maintain. The view is a pure function of `isFavorite` and the framework reacts.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Views/Sidebar/SessionRow.swift` — two modifiers.
- `docs/STAGE_2_ROADMAP.md` — P9.T04 → done.
