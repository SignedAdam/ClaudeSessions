# Cycle 72 — ScanRootStore (P10.T02)

**Singleton + JSON persistence,** mirroring FavoritesStore exactly so future readers don't have to learn a new pattern.

## What ships

`Sources/ClaudeSessions/Services/ScanRootStore.swift` — `@MainActor final class`, `static let shared`, `@Published private(set) var customRoots: [URL]`, persisted at `~/.claude-sessions-app/scan-roots.json`.

### Public surface

```swift
func allRoots() -> [URL]                 // [defaultRoot] + customRoots
@discardableResult
func addRoot(_ url: URL) -> String?      // nil on success, reason on rejection
func removeRoot(_ url: URL)
static let defaultRoot: URL              // ~/.claude/projects/, implicit
static func rootKey(for url: URL) -> String   // canonical key for diffing
```

### Validation

`addRoot` rejects with a human-readable reason when:
- the path isn't a directory,
- the directory isn't readable,
- the URL resolves to the default root,
- a custom root with the same canonical key already exists.

The canonical key uses `URL.resolvingSymlinksInPath().standardizedFileURL.path` then a base-36 stringified hash, so two paths that point at the same place via different symlinks de-dupe correctly.

### Wiring

`ClaudeSessionsApp.swift` — added `@StateObject private var scanRootStore = ScanRootStore.shared` and `.environmentObject(scanRootStore)` on both the WindowGroup root and the Settings scene. T03 (settings panel) and T04 (multi-root scanner) consume it from there.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Services/ScanRootStore.swift` (new).
- `Sources/ClaudeSessions/ClaudeSessionsApp.swift` — env injection.
- `docs/STAGE_2_ROADMAP.md` — P10.T02 → done.
