# Cycle 35 — MCP navigation tools (P3.T03)

**Task:** First batch of MCP tools — `list_projects`, `list_sessions(project_id?)`, `open_session(session_id)`, `close_session()`.

## What I built

### `Services/MCPTools/MCPNavigationTools.swift`

Four `MCPServer.ToolDescriptor`s with proper JSON Schema for the inputs:

- `list_projects` — `{ projects: [{id, name, originalPath, sessionCount}] }`.
- `list_sessions` — optional `project_id` filter. Returns `{ sessions: [{id, title, firstPrompt, messageCount, modified, projectId, projectName, isSubagent}] }`, sorted newest-first.
- `open_session` — required `session_id`. Looks up via `appState.findSession(id:)`, calls `appState.selectSession(...)`, returns `{opened: true, id, title, projectPath, messageCount}` or throws `notFound`.
- `close_session` — calls `appState.closeCurrentSession()`. Returns `{closed: true|false}` (false if nothing was open).

All four handlers are async and use `await MainActor.run { ... }` before touching `AppState` (which is `@MainActor`). The MCP server's queue dispatches them off the main thread, then bounces back when the handler needs UI state.

### `MCPToolError`

Shared error enum (`badArgument`, `notFound`, `unavailable`) so the next tool cycles (T04–T06) can throw consistently. The MCP server already maps thrown errors to JSON-RPC `-32000` responses with the error description in the `message` field.

### AppState wiring

Added a `bootstrapMCPTools()` method, called via `DispatchQueue.main.async { [weak self] in self?.bootstrapMCPTools() }` from `init()`. The deferred dispatch is necessary because closures inside the descriptors capture `self`, which can't be referenced inside a `nonisolated init`'s body for a `@MainActor` class. A guard flag (`didBootstrapMCP`) makes it idempotent.

Tools register but the server itself is still not started — that's T07's settings-toggle job.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/MCPTools/MCPNavigationTools.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (bootstrap hook)
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
