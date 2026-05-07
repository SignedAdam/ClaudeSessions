# Cycle 77 — Subagent polish (P10.T07) — Phase 10 complete

**Two cosmetic moves and a state-persistence fix.**

## 1. Count badge on the sidebar sparkle button

`FooterIconButton` got an optional `badge: Int?` prop. When set and > 0, a small toolTint capsule renders in the top-right corner with the number (or `99+`). SidebarFooter computes `subagentCount` directly:

```swift
private var subagentCount: Int {
    appState.projects.reduce(0) { acc, p in
        acc + p.sessions.reduce(0) { $0 + $1.subagents.count }
    }
}
```

This is O(parents) — much cheaper than calling `SubagentIndex.build` just to read `count`. The full index only lives inside the sheet, where it's needed.

## 2. Persisted filter

`SubagentsView`'s search query was `@State`, so closing and reopening the sheet wiped it. Switched to `@AppStorage("subagentsFilter")` — survives close-reopen and (as a side benefit) survives app relaunches. No new flags or settings; just one decorator change.

## 3. Empty state

Already shipped in cycle 76 — re-checked, kept as-is. Sparkles icon + "No subagent runs yet" + a sentence explaining what subagents are and where they come from. Good enough.

## Phase 10 status

All 7 tasks done. The Stage 2 roadmap is now fully closed:

- T01 audit ✅
- T02 ScanRootStore ✅
- T03 Locations settings panel ✅
- T04 Multi-root scanner cutover ✅
- T05 SubagentIndex ✅
- T06 SubagentsView browser ✅
- T07 polish ✅

The Decomposition queue is empty. Next cycle should detect that every task is `done`/`skipped`/`blocked` and write the final summary cycle note per loop step 4.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift` — FooterIconButton badge prop, subagentCount computed, sparkle button wired.
- `Sources/ClaudeSessions/Views/SubagentsView.swift` — `@State` → `@AppStorage` for filter.
- `docs/STAGE_2_ROADMAP.md` — P10.T07 → done.
