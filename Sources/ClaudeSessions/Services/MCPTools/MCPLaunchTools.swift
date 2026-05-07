import Foundation

/// MCP tools that drive Claude Code from inside Claude Sessions:
/// `extract_and_open` (clean dialogue → new resumable JSONL → open in CLI)
/// and `resume_in_terminal` (open the session as-is in the user's terminal).
///
/// Both are user-visible: they spawn terminal processes and write files.
/// Marked accordingly in their tool descriptions so MCP clients know to
/// ask before invoking.
enum MCPLaunchTools {

    static func register(server: MCPServer, appState: AppState) {
        server.register([
            extractAndOpenDescriptor(appState: appState),
            resumeInTerminalDescriptor(appState: appState)
        ])
    }

    // MARK: - extract_and_open

    private static func extractAndOpenDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "extract_and_open",
            description: "Strip tools/system noise from a session, leaving only the human↔Claude dialogue, and open the cleaned conversation in Claude Code. Mode 'new_session' writes a new resumable JSONL alongside the original; mode 'piped' pipes the dialogue into a fresh `claude` invocation. The original session is never modified. Spawns a terminal — clients should warn the user before calling.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string", "description": "Session id to extract from."],
                    "mode": [
                        "type": "string",
                        "enum": ["new_session", "piped"],
                        "description": "Optional. Defaults to the user's setting (typically 'new_session')."
                    ]
                ],
                "required": ["session_id"],
                "additionalProperties": false
            ],
            handler: { args in
                guard let id = args["session_id"] as? String, !id.isEmpty else {
                    throw MCPToolError.badArgument("session_id required")
                }
                // Resolve session + open it in the UI so the existing
                // extractAndOpenInClaude() flow (which acts on the open
                // conversation) has something to work with.
                guard let info = await MainActor.run(body: { appState.findSession(id: id) }) else {
                    throw MCPToolError.notFound("no session with id \(id)")
                }
                await appState.selectSession(info)

                // Mode override: temporarily flip the AppStorage if a mode
                // was specified, then restore. The extract methods read
                // from AppStorage directly. Simpler: call the mode-specific
                // method instead of the dispatcher.
                let modeStr = args["mode"] as? String
                let conversation = await MainActor.run { appState.currentConversation }
                guard let conv = conversation else {
                    throw MCPToolError.unavailable("conversation failed to load")
                }
                let cwd = conv.resolvedCwd
                guard let cwd = cwd else {
                    throw MCPToolError.unavailable("could not resolve project cwd for session \(id)")
                }
                await MainActor.run {
                    switch modeStr {
                    case "piped":
                        appState.extractAsPipedPrompt(conversation: conv, cwd: cwd)
                    case "new_session", nil, "":
                        appState.extractAsNewSession(conversation: conv, cwd: cwd)
                    default:
                        // Unknown mode — fall back to the user's default.
                        appState.extractAndOpenInClaude()
                    }
                }
                return [
                    "id": id,
                    "mode": modeStr ?? "new_session",
                    "launched": true
                ]
            }
        )
    }

    // MARK: - resume_in_terminal

    private static func resumeInTerminalDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "resume_in_terminal",
            description: "Open this session in the user's terminal via `claude --resume <id>` from the project's working directory. The session continues in place — Claude Code appends to the same JSONL. Spawns a terminal — clients should warn the user before calling.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string", "description": "Session id to resume."]
                ],
                "required": ["session_id"],
                "additionalProperties": false
            ],
            handler: { args in
                guard let id = args["session_id"] as? String, !id.isEmpty else {
                    throw MCPToolError.badArgument("session_id required")
                }
                guard let info = await MainActor.run(body: { appState.findSession(id: id) }) else {
                    throw MCPToolError.notFound("no session with id \(id)")
                }
                // Resolve cwd via the same SlugResolver path the toolbar uses.
                // Easiest: open the session briefly to get its conversation,
                // then read resolvedCwd. Falls back to projectPath if needed.
                let cwd: String? = {
                    if let recorded = info.projectPath { return recorded }
                    return nil
                }()

                // Better: use the loaded conversation if open, otherwise fall
                // back to projectPath. Don't force-open the session — that
                // would change the UI more than necessary for a CLI launch.
                let resolved: String? = await MainActor.run {
                    if let conv = appState.currentConversation, conv.sessionId == id {
                        return conv.resolvedCwd
                    }
                    return cwd
                }
                guard let cwd = resolved else {
                    throw MCPToolError.unavailable("could not resolve project cwd for session \(id)")
                }

                ProcessLauncher.resumeSession(sessionId: id, cwd: cwd)
                return [
                    "id": id,
                    "cwd": cwd,
                    "launched": true
                ]
            }
        )
    }
}
