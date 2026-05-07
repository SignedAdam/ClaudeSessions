# Cycle 37 — MCP organize tools (P3.T05)

**Task:** Eight MCP tools that mutate user-facing organization: star/unstar, hide/unhide, archive/unarchive, move-to-project, delete-to-Trash.

## What I built

`Services/MCPTools/MCPOrganizeTools.swift`. Each tool is a thin wrapper around an existing Swift method:

| Tool | Backend |
|---|---|
| `star` / `unstar` | `FavoritesStore.shared.add(id) / .remove(id)` |
| `hide` / `unhide` | `HiddenStore.shared.hideSession(id) / .unhideSession(id)` |
| `archive` | `appState.archiveSession(SessionInfo)` (moves to `~/.claude-sessions-archive/`) |
| `unarchive` | `archiveService.listArchived()` lookup → `appState.restoreArchivedSession(entry)` |
| `move_to_project` | `appState.copySessionToProject(session, source, target)` (copies, leaves source intact) |
| `delete_to_trash` | `appState.confirmDeleteSession(SessionInfo)` (`NSWorkspace.shared.recycle`) |

All bounce to `@MainActor` before touching state. Schemas attached. `delete_to_trash` description explicitly notes it's destructive and clients should confirm before calling — the macOS Trash is the safety net.

Total registered tools now: 4 (nav) + 3 (read) + 8 (organize) = **15**.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/MCPTools/MCPOrganizeTools.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (register call)
- Edit: `docs/STAGE_2_ROADMAP.md` — T05 → done
