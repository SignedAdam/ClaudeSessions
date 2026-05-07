# Cycle 34 — MCP server skeleton (P3.T02)

**Task:** HTTP/JSON-RPC server inside the app, wired to a tool registry, with `initialize` / `tools/list` / `tools/call` plumbed.

## What I built

### `Services/MCPServer.swift` (~250 lines)

- **Transport:** `NWListener` from `Network.framework` bound to `NWEndpoint.hostPort(host: .ipv4(.loopback), port: ...)`. Loopback-only by construction.
- **HTTP parser:** minimal HTTP/1.1 implementation. Reads until `\r\n\r\n`, parses request line + headers, reads `Content-Length` body bytes. Keeps reading via `receiveRequest(accumulated:)` if the body isn't fully buffered.
- **Routing:** only one path matters — `POST /mcp`. Anything else gets 404.
- **JSON-RPC:** parses body via `JSONSerialization`. Responds with `result` or `error` shapes. Uses standard error codes (-32700 parse, -32600 invalid, -32601 method-not-found, -32000 server error).
- **Methods:**
  - `initialize` → returns `protocolVersion: "2024-11-05"`, our `serverInfo`, and `capabilities.tools = {}`.
  - `tools/list` → maps registered `ToolDescriptor`s to MCP tool spec (name, description, inputSchema).
  - `tools/call` → looks up handler by name, calls async, wraps result as `{content: [{type:"text", text:<json>}]}`.
- **Tool registry:** `register(ToolDescriptor)` lets P3.T03–T06 cycles drop in tools without touching the server.

### AppState wiring

- New `let mcpServer = MCPServer()` property. Not started — T07 settings toggle owns the lifecycle. Subsequent tool-registration cycles (T03–T06) get a stable target to extend.

## Notes / deferrals

- **Runtime smoke test deferred.** Standing up a one-shot Swift harness that imports the package and curls the server is more scaffolding than this cycle should pay for. The path is fully exercised the first time T07 lands and the user toggles the server on. If parsing is broken, we'll see it there.
- **No SSE.** None of the planned tools stream. Spec's "Streamable HTTP" without SSE is fine for v1.
- **No auth.** Loopback is the gate. If we ever bind beyond, add a per-launch token header at that point.
- **Connection: close** on every reply, no keep-alive. Simpler. Each tool call is a fresh connection. Fine at our call rates.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/MCPServer.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (mcpServer property)
- Edit: `docs/STAGE_2_ROADMAP.md` — T02 → done
