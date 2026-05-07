import Foundation

// MARK: - Project & Session

struct Project: Identifiable, Equatable {
    let id: String
    let name: String
    let originalPath: String
    var sessions: [SessionInfo]

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id && lhs.sessions.count == rhs.sessions.count
    }
}

struct SessionInfo: Identifiable {
    let id: String
    let filePath: String
    let title: String
    let firstPrompt: String?
    let messageCount: Int
    let created: Date
    let modified: Date
    let gitBranch: String?
    let projectPath: String?
    let isFromIndex: Bool
    /// Subagent sessions that ran *under* this session. Stored in
    /// `<project>/<sessionId>/subagents/agent-*.jsonl` by Claude Code.
    var subagents: [SessionInfo] = []
    /// True for sessions inside a `subagents/` directory. Used to render
    /// them with indentation and a different icon in the sidebar.
    var isSubagent: Bool = false
}

// MARK: - Conversation

struct Conversation {
    let sessionId: String
    let filePath: String
    var displayMessages: [DisplayMessage]
    var rawEntries: [IndexedEntry]
    var stats: ConversationStats
    var isDirty: Bool = false
    var deletedIndices: Set<Int> = []

    /// Real on-disk cwd, resolved via slug (filesystem-grounded) and falling
    /// back to the recorded `cwd` field if needed.
    var resolvedCwd: String? {
        let recorded = rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd
        let parentDir = (filePath as NSString).deletingLastPathComponent
        let slug = (parentDir as NSString).lastPathComponent
        return SlugResolver.bestCwd(slug: slug, recorded: recorded)
    }
}

struct IndexedEntry {
    let index: Int
    let rawJSON: String
    var entry: RawEntry
    var isModified: Bool = false
    var isDeleted: Bool = false
}

struct ConversationStats {
    let userMessageCount: Int
    let assistantMessageCount: Int
    let toolCallCount: Int
    let systemMessageCount: Int
    let firstTimestamp: Date?
    let lastTimestamp: Date?

    var duration: TimeInterval? {
        guard let first = firstTimestamp, let last = lastTimestamp else { return nil }
        return last.timeIntervalSince(first)
    }
}

// MARK: - Display Message

enum DisplayMessage: Identifiable {
    case userText(UserTextMessage)
    case assistantText(AssistantTextMessage)
    case toolInteraction(ToolInteraction)
    case toolCall(ToolCallMessage)
    case toolResult(ToolResultMessage)
    case systemMessage(SystemDisplayMessage)
    case compactBoundary(CompactBoundaryMessage)

    var id: String {
        switch self {
        case .userText(let m): return m.id
        case .assistantText(let m): return m.id
        case .toolInteraction(let m): return m.id
        case .toolCall(let m): return m.id
        case .toolResult(let m): return m.id
        case .systemMessage(let m): return m.id
        case .compactBoundary(let m): return m.id
        }
    }

    var timestamp: Date? {
        switch self {
        case .userText(let m): return m.timestamp
        case .assistantText(let m): return m.timestamp
        case .toolInteraction(let m): return m.toolCall.timestamp
        case .toolCall(let m): return m.timestamp
        case .toolResult(let m): return m.timestamp
        case .systemMessage(let m): return m.timestamp
        case .compactBoundary(let m): return m.timestamp
        }
    }

    var entryIndex: Int {
        switch self {
        case .userText(let m): return m.entryIndex
        case .assistantText(let m): return m.entryIndex
        case .toolInteraction(let m): return m.toolCall.entryIndex
        case .toolCall(let m): return m.entryIndex
        case .toolResult(let m): return m.entryIndex
        case .systemMessage(let m): return m.entryIndex
        case .compactBoundary(let m): return m.entryIndex
        }
    }

    /// Whether this message should be visible given the current filter state
    func isVisible(showUser: Bool, showAssistant: Bool, showTool: Bool, showSystem: Bool) -> Bool {
        switch self {
        case .userText: return showUser
        case .assistantText: return showAssistant
        case .toolInteraction, .toolCall, .toolResult: return showTool
        case .systemMessage, .compactBoundary: return showSystem
        }
    }
}

// MARK: - Concrete Message Types

struct UserTextMessage: Identifiable {
    let id: String
    var text: String
    let timestamp: Date?
    /// Raw ISO string preserved so we can render sub-second precision when present.
    let timestampRaw: String?
    let isCompactSummary: Bool
    let entryIndex: Int
}

struct AssistantTextMessage: Identifiable {
    let id: String
    var text: String
    let timestamp: Date?
    let timestampRaw: String?
    let model: String?
    let isApiError: Bool
    let tokenUsage: UsageInfo?
    let entryIndex: Int
    let blockIndex: Int
}

struct ToolInteraction: Identifiable {
    let id: String
    let toolCall: ToolCallMessage
    let toolResult: ToolResultMessage?
}

struct ToolCallMessage: Identifiable {
    let id: String
    let toolName: String
    let input: [String: Any]
    let description: String?
    let summary: String
    let timestamp: Date?
    let entryIndex: Int
}

struct ToolResultMessage: Identifiable {
    let id: String
    let toolUseId: String
    let resultText: String
    let isError: Bool
    let timestamp: Date?
    let entryIndex: Int
}

struct SystemDisplayMessage: Identifiable {
    let id: String
    let subtype: String
    let content: String
    let timestamp: Date?
    let durationMs: Int?
    let entryIndex: Int
}

struct CompactBoundaryMessage: Identifiable {
    let id: String
    let timestamp: Date?
    let preTokens: Int?
    let trigger: String?
    let entryIndex: Int
}
