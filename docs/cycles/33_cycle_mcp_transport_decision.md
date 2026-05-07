# Cycle 33 — MCP transport decision (P3.T01)

**Task:** Pick MCP transport (stdio vs HTTP) and document the choice so the next cycles have a stable target.

## Decision

**HTTP on localhost.** Streamable HTTP variant, no SSE. JSON-RPC 2.0 over `POST /mcp`. Default port 7531, configurable. Bound to `127.0.0.1` only.

## Why

- Our app is already a long-lived GUI process — it makes sense to host the server inside it instead of spawning a separate stdio subprocess that has to IPC back to the GUI for every state-touching call.
- Several planned tools (`open_session`, `close_session`, `extract_and_open`) mutate visible UI state. The GUI process owns that state.
- HTTP is debuggable with `curl`; stdio is not.
- Localhost-only binding is good enough for v1: anyone with code execution on the box can already read the same files directly. If we ever bind beyond loopback, add a per-launch token header at that point.

## Implications recorded in roadmap

- T02 will use `Network.framework`'s `NWListener` / `NWConnection` (Apple-blessed, no external deps).
- T03–T06: plain handler functions; a thin wrapper turns them into MCP tool descriptors.
- T07: Settings UI with enable/disable, port field, and a "Copy snippet" button for the user's `~/.claude/settings.json`.
- No SSE this cycle — none of our planned tools stream. Add later if a `subscribe` tool appears.

## Build status

No code changes — research/decision only.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T01 → done with full findings.
- `docs/cycles/33_cycle_mcp_transport_decision.md` — this note.
