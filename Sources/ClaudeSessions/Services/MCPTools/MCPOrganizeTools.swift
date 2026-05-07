import Foundation

/// MCP tools that mutate the user's organization of sessions:
/// star/unstar, hide/unhide, archive/unarchive, move-to-project,
/// delete-to-Trash. All thin wrappers around existing AppState +
/// FavoritesStore + HiddenStore + ArchiveService methods.
///
/// All handlers bounce to @MainActor before touching app state.
enum MCPOrganizeTools {

    static func register(server: MCPServer, appState: AppState) {
        server.register([
            starDescriptor(appState: appState, set: true),
            starDescriptor(appState: appState, set: false),
            hideDescriptor(appState: appState, set: true),
            hideDescriptor(appState: appState, set: false),
            archiveDescriptor(appState: appState),
            unarchiveDescriptor(appState: appState),
            moveToProjectDescriptor(appState: appState),
            deleteToTrashDescriptor(appState: appState)
        ])
    }

    // MARK: - star / unstar

    private static func starDescriptor(appState: AppState, set: Bool) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: set ? "star" : "unstar",
            description: set
                ? "Mark a session as starred. Starred sessions appear in the Favorites section at the top of the sidebar."
                : "Remove a session from the Favorites section.",
            inputSchema: idOnlySchema(label: "session_id", required: true),
            handler: { args in
                let id = try requireSessionId(args)
                await MainActor.run {
                    if set { FavoritesStore.shared.add(id) }
                    else   { FavoritesStore.shared.remove(id) }
                }
                return ["id": id, "starred": set]
            }
        )
    }

    // MARK: - hide / unhide

    private static func hideDescriptor(appState: AppState, set: Bool) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: set ? "hide" : "unhide",
            description: set
                ? "Hide a session from the sidebar. Visual-only — the file stays in place. The user can re-show with 'unhide' or by toggling 'show hidden' in the sidebar."
                : "Restore a previously hidden session to the sidebar.",
            inputSchema: idOnlySchema(label: "session_id", required: true),
            handler: { args in
                let id = try requireSessionId(args)
                await MainActor.run {
                    if set { HiddenStore.shared.hideSession(id) }
                    else   { HiddenStore.shared.unhideSession(id) }
                }
                return ["id": id, "hidden": set]
            }
        )
    }

    // MARK: - archive

    private static func archiveDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "archive",
            description: "Move a session out of `~/.claude/projects/` and into `~/.claude-sessions-archive/`. Claude Code's resume picker stops seeing it; the file is preserved and can be restored.",
            inputSchema: idOnlySchema(label: "session_id", required: true),
            handler: { args in
                let id = try requireSessionId(args)
                guard let info = await MainActor.run(body: { appState.findSession(id: id) }) else {
                    throw MCPToolError.notFound("no session with id \(id)")
                }
                await appState.archiveSession(info)
                return ["id": id, "archived": true]
            }
        )
    }

    // MARK: - unarchive

    private static func unarchiveDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "unarchive",
            description: "Restore a previously archived session back to its original project directory.",
            inputSchema: idOnlySchema(label: "session_id", required: true),
            handler: { args in
                let id = try requireSessionId(args)
                let archiveService = await MainActor.run { appState.archiveService }
                let entries = archiveService.listArchived()
                guard let entry = entries.first(where: { $0.sessionId == id }) else {
                    throw MCPToolError.notFound("no archived session with id \(id)")
                }
                await appState.restoreArchivedSession(entry)
                return ["id": id, "restored": true, "originalPath": entry.originalPath]
            }
        )
    }

    // MARK: - move_to_project

    private static func moveToProjectDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "move_to_project",
            description: "Copy a session into another project's slug directory (the source is left untouched, matching the in-app 'Copy to Project' UX). Names the copy `moved from <src> · <orig title>`.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string", "description": "Session id to copy."],
                    "target_project_id": ["type": "string", "description": "Project id (slug) to copy into."]
                ],
                "required": ["session_id", "target_project_id"],
                "additionalProperties": false
            ],
            handler: { args in
                let sessionId = try requireSessionId(args)
                guard let targetId = args["target_project_id"] as? String, !targetId.isEmpty else {
                    throw MCPToolError.badArgument("target_project_id required")
                }
                let lookup: (SessionInfo, Project, Project)? = await MainActor.run {
                    let projects = appState.projects
                    guard let target = projects.first(where: { $0.id == targetId }) else { return nil }
                    for p in projects {
                        if let s = p.sessions.first(where: { $0.id == sessionId }) {
                            return (s, p, target)
                        }
                    }
                    return nil
                }
                guard let (session, source, target) = lookup else {
                    throw MCPToolError.notFound("session or target project not found")
                }
                await appState.copySessionToProject(session: session,
                                                    sourceProject: source,
                                                    target: target)
                return [
                    "id": sessionId,
                    "movedFrom": source.id,
                    "movedTo": target.id
                ]
            }
        )
    }

    // MARK: - delete_to_trash

    private static func deleteToTrashDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "delete_to_trash",
            description: "Move a session's JSONL file to the macOS Trash. Recoverable from Trash until emptied. The file is removed from `sessions-index.json` too. This is a destructive action — clients should confirm with the user before calling.",
            inputSchema: idOnlySchema(label: "session_id", required: true),
            handler: { args in
                let id = try requireSessionId(args)
                guard let info = await MainActor.run(body: { appState.findSession(id: id) }) else {
                    throw MCPToolError.notFound("no session with id \(id)")
                }
                await appState.confirmDeleteSession(info)
                return ["id": id, "trashed": true]
            }
        )
    }

    // MARK: - Helpers

    private static func idOnlySchema(label: String, required: Bool) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": [
                label: ["type": "string", "description": "The session id."]
            ],
            "additionalProperties": false
        ]
        if required {
            schema["required"] = [label]
        }
        return schema
    }

    private static func requireSessionId(_ args: [String: Any]) throws -> String {
        guard let id = args["session_id"] as? String, !id.isEmpty else {
            throw MCPToolError.badArgument("session_id required")
        }
        return id
    }
}
