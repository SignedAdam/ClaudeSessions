import Foundation

/// MCP tools that let an external client navigate the app's project /
/// session tree and open or close conversations.
///
/// All handlers run on the MCP server's queue but bounce to @MainActor
/// before touching AppState — AppState is main-actor isolated.
enum MCPNavigationTools {

    static func register(server: MCPServer, appState: AppState) {
        server.register([
            listProjectsDescriptor(appState: appState),
            listSessionsDescriptor(appState: appState),
            openSessionDescriptor(appState: appState),
            closeSessionDescriptor(appState: appState)
        ])
    }

    // MARK: - list_projects

    private static func listProjectsDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "list_projects",
            description: "List every project that has at least one Claude Code session. Returns id, name, original path, and session count for each.",
            inputSchema: ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            handler: { _ in
                let projects = await MainActor.run { appState.projects }
                let payload = projects.map { p in
                    [
                        "id": p.id,
                        "name": p.name,
                        "originalPath": p.originalPath,
                        "sessionCount": p.sessions.count
                    ] as [String: Any]
                }
                return ["projects": payload]
            }
        )
    }

    // MARK: - list_sessions

    private static func listSessionsDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "list_sessions",
            description: "List sessions, optionally filtered to one project. Returns id, title, first prompt, message count, modified timestamp, and project id for each. Sessions are sorted newest-first.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "project_id": [
                        "type": "string",
                        "description": "Optional. The project id (slug) to filter by. If omitted, returns sessions from all projects."
                    ]
                ],
                "additionalProperties": false
            ],
            handler: { args in
                let filter = args["project_id"] as? String
                let projects = await MainActor.run { appState.projects }
                var rows: [[String: Any]] = []
                for project in projects {
                    if let f = filter, f != project.id { continue }
                    for s in project.sessions {
                        rows.append([
                            "id": s.id,
                            "title": s.title,
                            "firstPrompt": s.firstPrompt as Any,
                            "messageCount": s.messageCount,
                            "modified": ISO8601DateFormatter().string(from: s.modified),
                            "projectId": project.id,
                            "projectName": project.name,
                            "isSubagent": s.isSubagent
                        ])
                    }
                }
                rows.sort { ($0["modified"] as? String ?? "") > ($1["modified"] as? String ?? "") }
                return ["sessions": rows]
            }
        )
    }

    // MARK: - open_session

    private static func openSessionDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "open_session",
            description: "Open a conversation in the Claude Sessions UI. The user sees the conversation appear in the main pane. Returns the session's basic metadata once loaded.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "session_id": [
                        "type": "string",
                        "description": "The session id (UUID, or `agent-…` for subagent sessions)."
                    ]
                ],
                "required": ["session_id"],
                "additionalProperties": false
            ],
            handler: { args in
                guard let id = args["session_id"] as? String, !id.isEmpty else {
                    throw MCPToolError.badArgument("session_id required")
                }
                let info: SessionInfo? = await MainActor.run { appState.findSession(id: id) }
                guard let info else {
                    throw MCPToolError.notFound("no session with id \(id)")
                }
                await appState.selectSession(info)
                let title = await MainActor.run { appState.currentSessionTitle ?? info.title }
                return [
                    "opened": true,
                    "id": info.id,
                    "title": title,
                    "projectPath": info.projectPath as Any,
                    "messageCount": info.messageCount
                ]
            }
        )
    }

    // MARK: - close_session

    private static func closeSessionDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "close_session",
            description: "Close the currently open conversation and return to the dashboard. No-op if nothing is open.",
            inputSchema: ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            handler: { _ in
                let wasOpen: Bool = await MainActor.run {
                    let openId = appState.selectedSessionId
                    appState.closeCurrentSession()
                    return openId != nil
                }
                return ["closed": wasOpen]
            }
        )
    }
}

// MARK: - Errors

enum MCPToolError: Error, LocalizedError {
    case badArgument(String)
    case notFound(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .badArgument(let s): return "bad argument: \(s)"
        case .notFound(let s):    return "not found: \(s)"
        case .unavailable(let s): return "unavailable: \(s)"
        }
    }
}
