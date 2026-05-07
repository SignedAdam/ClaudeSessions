# Cycle 36 — MCP read tools (P3.T04)

**Task:** Three tools that let an MCP client read a conversation: metadata only, dialogue only, or the full transcript.

## What I built

### `Services/MCPTools/MCPReadTools.swift`

- `read_session_metadata` — returns `id, title, firstPrompt, messageCount, created, modified, gitBranch, projectPath, filePath, isSubagent`. No JSONL parse — uses `appState.findSession(id:)`.
- `read_dialogue_only` — parses the JSONL via `ConversationParser`, filters to `userText` + `assistantText` (skipping compact-summary user entries and api-error assistant entries), formats via `ClipboardService.formatFullTranscript` with empty edits/deletions sets. Returns `{id, messageCount, text}`.
- `read_full_transcript` — same but no filter; every visible event including tool calls, tool results, and system messages.

Heavy reads (dialogue, transcript) parse JSONL inside a `Task.detached(priority: .userInitiated)` so they don't block the MCP server queue or any other actor. They share the existing 25MB ceiling we use in `AppState.performLoad` (so a wedged daemon can't OOM the GUI).

### Registration

Wired into `AppState.bootstrapMCPTools()` alongside the navigation tools. Both register at the same time so the server has all six tools at once.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/MCPTools/MCPReadTools.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (additional register call)
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
