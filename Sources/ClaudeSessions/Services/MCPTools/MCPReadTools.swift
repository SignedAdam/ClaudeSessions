import Foundation

/// MCP tools for reading the contents of a conversation.
///
/// Three flavors:
///   - `read_session_metadata` — quick info about the session (no JSONL parse).
///   - `read_dialogue_only`   — just human ↔ Claude text.
///   - `read_full_transcript` — every message including tools / system.
///
/// Heavy reads (full transcript, dialogue) parse the JSONL on the fly via
/// the same ConversationParser the UI uses. Off-main to keep the UI alive.
enum MCPReadTools {

    static func register(server: MCPServer, appState: AppState) {
        server.register([
            metadataDescriptor(appState: appState),
            dialogueDescriptor(appState: appState),
            transcriptDescriptor(appState: appState)
        ])
    }

    // MARK: - read_session_metadata

    private static func metadataDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "read_session_metadata",
            description: "Quick metadata about a session — title, project, message count, dates, paths. Doesn't load the conversation body.",
            inputSchema: idOnlySchema(),
            handler: { args in
                let id = try requireSessionId(args)
                guard let info = await MainActor.run(body: { appState.findSession(id: id) }) else {
                    throw MCPToolError.notFound("no session with id \(id)")
                }
                let iso = ISO8601DateFormatter()
                return [
                    "id": info.id,
                    "title": info.title,
                    "firstPrompt": info.firstPrompt as Any,
                    "messageCount": info.messageCount,
                    "created": iso.string(from: info.created),
                    "modified": iso.string(from: info.modified),
                    "gitBranch": info.gitBranch as Any,
                    "projectPath": info.projectPath as Any,
                    "filePath": info.filePath,
                    "isSubagent": info.isSubagent
                ]
            }
        )
    }

    // MARK: - read_dialogue_only

    private static func dialogueDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "read_dialogue_only",
            description: "The human ↔ Claude dialogue from a session as plain text. Strips tool calls, tool results, system events, and any compact-summary noise. Equivalent to the app's `clean` extract.",
            inputSchema: idOnlySchema(),
            handler: { args in
                let id = try requireSessionId(args)
                let conversation = try await loadConversation(id: id, appState: appState)
                let displayName = await MainActor.run { appState.displayName }
                let dialogueOnly = conversation.displayMessages.filter { msg in
                    switch msg {
                    case .userText(let m): return !m.isCompactSummary
                    case .assistantText(let m): return !m.isApiError
                    default: return false
                    }
                }
                let text = ClipboardService.formatFullTranscript(
                    displayMessages: dialogueOnly,
                    displayName: displayName,
                    editedTexts: [:],
                    deletedMessageIds: []
                )
                return [
                    "id": id,
                    "messageCount": dialogueOnly.count,
                    "text": text
                ]
            }
        )
    }

    // MARK: - read_full_transcript

    private static func transcriptDescriptor(appState: AppState) -> MCPServer.ToolDescriptor {
        MCPServer.ToolDescriptor(
            name: "read_full_transcript",
            description: "The complete transcript — every visible event, including tool calls, tool results, and system messages. Plain text.",
            inputSchema: idOnlySchema(),
            handler: { args in
                let id = try requireSessionId(args)
                let conversation = try await loadConversation(id: id, appState: appState)
                let displayName = await MainActor.run { appState.displayName }
                let text = ClipboardService.formatFullTranscript(
                    displayMessages: conversation.displayMessages,
                    displayName: displayName,
                    editedTexts: [:],
                    deletedMessageIds: []
                )
                return [
                    "id": id,
                    "messageCount": conversation.displayMessages.count,
                    "text": text
                ]
            }
        )
    }

    // MARK: - Helpers

    private static func idOnlySchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": [
                    "type": "string",
                    "description": "The session id."
                ]
            ],
            "required": ["session_id"],
            "additionalProperties": false
        ]
    }

    private static func requireSessionId(_ args: [String: Any]) throws -> String {
        guard let id = args["session_id"] as? String, !id.isEmpty else {
            throw MCPToolError.badArgument("session_id required")
        }
        return id
    }

    /// Load + parse a session's JSONL by id. Refuses files larger than
    /// 25MB — same ceiling AppState uses for the in-app loader.
    private static func loadConversation(id: String, appState: AppState) async throws -> Conversation {
        guard let info = await MainActor.run(body: { appState.findSession(id: id) }) else {
            throw MCPToolError.notFound("no session with id \(id)")
        }

        let path = info.filePath
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        if size > 25_000_000 {
            throw MCPToolError.unavailable("session file too large to load (\(size) bytes)")
        }

        return try await Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else {
                throw MCPToolError.unavailable("could not read \(path)")
            }
            return ConversationParser().parse(data: data, sessionId: id, filePath: path)
        }.value
    }
}
