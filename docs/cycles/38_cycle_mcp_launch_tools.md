# Cycle 38 — MCP launch tools (P3.T06)

**Task:** Two MCP tools that drive Claude Code: `extract_and_open(session_id, mode)` and `resume_in_terminal(session_id)`.

## What I built

`Services/MCPTools/MCPLaunchTools.swift`. Two tools:

- `extract_and_open` — opens the session in the UI (so the existing extract flow has something to work with), then dispatches to `appState.extractAsNewSession(...)` or `appState.extractAsPipedPrompt(...)` based on the `mode` argument (`"new_session"` default, or `"piped"`). The tool description warns clients it spawns a terminal.
- `resume_in_terminal` — finds the session, resolves `cwd` (preferring the loaded conversation's `resolvedCwd` if open, otherwise the SessionInfo's `projectPath`), and calls `ProcessLauncher.resumeSession(sessionId:cwd:displayName:)`. Same terminal-spawn warning in the description.

Both bounce through `@MainActor` for state reads and writes.

## Phase 3 status

- T01 ✅ transport decision
- T02 ✅ skeleton
- T03 ✅ navigation tools (4)
- T04 ✅ read tools (3)
- T05 ✅ organize tools (8)
- **T06 ✅ launch tools (2)**
- T07 last (settings UI + start/stop the server)

**17 MCP tools** registered total. Server still inert — T07 wires the toggle that starts it.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/MCPTools/MCPLaunchTools.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (register call)
- Edit: `docs/STAGE_2_ROADMAP.md` — T06 → done
