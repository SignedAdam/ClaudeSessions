# Cycle 39 — MCP settings UI + lifecycle (P3.T07) — Phase 3 complete

**Task:** Surface the MCP server in Settings: enable toggle, port field, copy-snippet button.

## What I built

### `Views/Settings/MCPSettingsView.swift`

- **Header card** with antenna icon and explainer.
- **Enable toggle** bound through `AppState.setMCPEnabled(_:)`. Subtitle shows live status: "Running on http://127.0.0.1:7531/mcp" in green when up, "Stopped" muted when down.
- **Port field** with validation (1024 < port < 65535). Save button is disabled until the field changes; clicking it persists the value and calls `appState.restartMCPServer()` to bind the new port.
- **Copy snippet** for the user's `~/.claude/settings.json` mcpServers entry — populates the current port automatically. Button briefly shows "Copied" after click.
- **Tools list** as a reference of all 17 exposed tools, plus a heads-up that `delete_to_trash` and the launch tools have UI side-effects.

Wrapped in a `ScrollView` since this tab has more content than the others.

### AppState

- `@AppStorage("mcpServerEnabled")` (default false), `@AppStorage("mcpServerPort")` (default 7531).
- `setMCPEnabled(_ enabled: Bool)` — toggles the persistence flag and starts/stops the server accordingly.
- `restartMCPServer()` — stops + restarts so the new port takes effect.
- `startMCPServer()` — calls `mcpServer.start(port:)`, surfaces failures as toasts and reverts the flag to off so the UI doesn't claim "running" when it's not.
- On launch: if `mcpServerEnabled`, the server starts after `bootstrapMCPTools()` registers the 17 tools.

### `MCPServer`

Tweaked `start()` to take an optional `port: UInt16?` and update `self.port` if provided. Keeps `port` `private(set)` while letting AppState own the value of record.

### Settings tab

New "MCP" tab in `SettingsView`, between "Claude Code" and "AI Search".

## Phase 3 status

All seven tasks done:

- T01 ✅ transport decision (HTTP / 127.0.0.1)
- T02 ✅ server skeleton (NWListener + JSON-RPC)
- T03 ✅ navigation tools (4)
- T04 ✅ read tools (3)
- T05 ✅ organize tools (8)
- T06 ✅ launch tools (2)
- **T07 ✅ settings UI + lifecycle**

**17 MCP tools exposed.** The user can flip the toggle, paste the snippet into Claude Code's settings, and start saying things like "open the Stripe webhook conversation, extract dialogue, resume it" — Claude Code calls our tools to make it happen.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Views/Settings/MCPSettingsView.swift`
- Edit: `Sources/ClaudeSessions/Services/MCPServer.swift` (start(port:))
- Edit: `Sources/ClaudeSessions/AppState.swift` (lifecycle methods + persistence keys + launch hook)
- Edit: `Sources/ClaudeSessions/Views/Settings/SettingsView.swift` (new tab)
- Edit: `docs/STAGE_2_ROADMAP.md` — T07 → done, **Phase 3 complete**.
