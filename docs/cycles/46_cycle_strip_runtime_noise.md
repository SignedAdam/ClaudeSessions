# Cycle 46 — Strip runtime noise wrappers (P5.T02)

**Task:** Implement the strip in `CleanConversationService` per the cycle 45 reframe.

## What I did

Added `stripRuntimeNoise: Bool = true` parameter to `clean(...)`. Threaded through to `processUserEntry`. New static helper `stripNoiseWrappers(from:)`:

```swift
private static let noiseTags = [
    "system-reminder",
    "local-command-caveat",
    "command-stdout",
    "command-stderr"
]
```

For each tag, `NSRegularExpression` with `(?s)<tag\b[^>]*>.*?</tag>` removes the entire wrapper (including any attributes on the open tag). After all tags processed, `\n{3,}` → `\n\n` collapses leftover blank-line runs and the result is whitespace-trimmed.

Call sites untouched — they use the default `true`. Non-default behavior is available for future selective-strip work in T04.

## Caller integration

Default behavior of `extractAsNewSession` and `extractAsPipedPrompt` (in AppState) now produces strip-clean dialogue. The user-facing toggle for it lands in T03.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Services/CleanConversationService.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T02 → done
