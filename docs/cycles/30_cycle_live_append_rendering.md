# Cycle 30 — Live append rendering (P2.T04)

**Task:** When the JSONL grows during a `claude -p --resume` run, render the new entries with a "fresh" cue and auto-scroll to bottom.

## What I built

### Diff in AppState

When `selectSession` reloads a conversation that's the *same* sessionId as before (i.e. a FileWatcher trigger, not a sidebar click), compute the set difference between old and new `displayMessages` ids. If any are new:

- Stash them in `@Published var recentlyArrivedMessageIds: Set<String>`.
- Bump `@Published var lastAppendAt: Date` so views can react via `onChange`.
- Schedule a 1.5s task that subtracts those ids back out — that's the "freshness window."

Skipped diffing when:
- The previous load was a different session (`prior.sessionId != conversation.sessionId`).
- The previous load was empty (first time opening).

This way, `recentlyArrivedMessageIds` is empty on session-switch and only populates on real appends.

### `ConversationView`

- Added `bottomAnchorId` (`Spacer().frame(height: 8).id(...)`).
- `.onChange(of: appState.lastAppendAt)` → `proxy.scrollTo(bottomAnchorId, anchor: .bottom)` with `.easeOut(0.35)` animation. Gated on `recentlyArrivedMessageIds` non-empty so unrelated AppState changes don't trigger scrolls.
- For each freshly-arrived message: a 2pt accent-tinted strip on the leading edge (`overlay(alignment: .leading)`), fading out via `.animation(.easeOut(0.45), value: isFresh)` when the id leaves the set.

## Trade-offs

- **No "user has scrolled up" detection.** SwiftUI's ScrollView doesn't expose scroll offset cleanly. Implementing it requires a `GeometryReader` + custom `PreferenceKey` shim that's worth more bug surface than this is worth right now. Auto-scroll fires on every append; the user gets bumped to bottom even if they were reading earlier content. If that turns out to bite, follow-up.
- **Used overlay + accent strip instead of opacity fade-in.** SwiftUI's `transition(.opacity)` doesn't fire reliably inside `LazyVStack` for items that were *already* in the data tree (the diff doesn't see them as inserted, since the conversation re-loads via a wholesale assignment). Overlay + animation gives a more reliable cue without depending on diff semantics.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/AppState.swift` (diff logic, recentlyArrived state, lastAppendAt)
- Edit: `Sources/ClaudeSessions/Views/Conversation/ConversationView.swift` (auto-scroll, accent strip)
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
