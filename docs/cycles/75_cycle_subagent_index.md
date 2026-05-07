# Cycle 75 — SubagentIndex (P10.T05)

**Pure derivation cycle.** No new I/O — the data already lives in `Project.sessions[i].subagents` after the regular scan. The browser view (T06) consumes the result.

## What ships

`Sources/ClaudeSessions/Services/SubagentIndex.swift`:

```swift
struct SubagentIndexEntry: Identifiable {
    let id: String              // <projectId>::<parentId>::<subId>
    let subagent: SessionInfo
    let parent: SessionInfo
    let project: Project
    let agentName: String?      // best-effort, may be nil
}

enum SubagentIndex {
    static func build(from projects: [Project]) -> [SubagentIndexEntry]
    static func extractAgentName(fromFile path: String) -> String?
}
```

`build` triple-loops projects → parent sessions → subagents, builds the entries, sorts modified-desc. O(total subagent count).

## Agent name extraction

Filename convention is `agent-<NAME>-<uuid>.jsonl` where `<uuid>` is a standard 8-4-4-4-12 UUID (5 dash-separated parts). The extractor:

1. Confirms the `.jsonl` suffix and `agent-` prefix.
2. Strips both.
3. Splits on `-` and ensures at least 6 parts (≥1 name + 5 UUID).
4. Joins all but the last 5 with `-` to recover the name (so multi-word agent names like `code-reviewer` round-trip correctly).
5. Returns nil if anything doesn't conform.

This stays a best-effort: filenames that don't match the convention just show no agent name in the browser, not a parse error.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Services/SubagentIndex.swift` (new).
- `docs/STAGE_2_ROADMAP.md` — P10.T05 → done.
