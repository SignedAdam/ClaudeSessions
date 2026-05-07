# Cycle 74 — Multi-root ProjectScanner cutover (P10.T04)

**The cutover.** Through cycle 73 the multi-root code was dormant scaffolding. This cycle makes it live.

## Model change

`Project` gained two fields:

```swift
let id: String         // composite "<rootKey>:<slug>"
let slug: String       // bare directory name under sourceRoot
let sourceRoot: URL    // which scan root this came from
```

The composite id keeps SwiftUI's ForEach correct when two roots happen to host a project with the same slug. `slug` is preserved separately so anything that needs the bare directory name (e.g. ArchiveService's archive path) stays back-compat.

## Scanner refactor

Old: `func scan() async -> [Project]` reading a hardcoded path.
New:
- `func scan() async -> [Project]` — one-arg shim → `scan(roots: [ScanRootStore.defaultRoot])` for callers that don't know about the store.
- `func scan(roots: [URL]) async -> [Project]` — public entry point. Iterates each root via the private helper, concatenates, sorts by name.
- `private func scanOne(root: URL) async -> [Project]` — the original body, parameterized on `root`. Computes `rootKey` once and stamps each Project with `id = "<rootKey>:<slug>"`, `slug`, `sourceRoot = root`.

`AppState.loadProjects()` now does:

```swift
let roots = ScanRootStore.shared.allRoots()
let discovered = await scanner.scan(roots: roots)
```

## Threading fix

`ScanRootStore` is `@MainActor`, but `ProjectScanner` runs off-actor. The static helpers `rootKey(for:)` and `defaultRoot` are pure computation, so they're now `nonisolated static` — safe to call from any actor.

## ArchiveService — preserve back-compat

The archive layout is `~/.claude-sessions-archive/<projectId>/<sessionId>.jsonl`. Pre-cycle-74, projectId == slug; post-cycle-74, project.id == "<rootKey>:<slug>" (which would create new ugly directories and orphan existing archives). Switched the caller in `archiveSession` from `project.id` to `project.slug` — archive paths are exactly what they used to be, existing archives still work.

## Sidebar root tag

`ProjectSection` got an optional `rootTag: String?` prop. When non-nil, it renders next to the project name as a small monospaced pill (surface bg, textSecondary fg). `SidebarView` only populates it when more than one root is configured:

```swift
rootTag: scanRootStore.allRoots().count > 1
    ? project.sourceRoot.lastPathComponent
    : nil
```

So single-root users see *exactly* the old UI. Multi-root users see the tag on every project.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Models/DisplayModels.swift` — Project gains slug + sourceRoot, doc-comments on id.
- `Sources/ClaudeSessions/Services/ProjectScanner.swift` — multi-root refactor.
- `Sources/ClaudeSessions/Services/ScanRootStore.swift` — `nonisolated` on static helpers.
- `Sources/ClaudeSessions/AppState.swift` — loadProjects passes roots; archive uses project.slug.
- `Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift` — scanRootStore env, rootTag prop, conditional population.
- `docs/STAGE_2_ROADMAP.md` — P10.T04 → done.
