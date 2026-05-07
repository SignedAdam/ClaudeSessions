import Foundation

// MARK: - Entry Type

enum EntryType: String, Codable {
    case user
    case assistant
    case system
    case fileHistorySnapshot = "file-history-snapshot"
    case progress
    case queueOperation = "queue-operation"
    case lastPrompt = "last-prompt"
    case customTitle = "custom-title"
    case permissionModeEntry = "permission-mode"
    case agentNameEntry = "agent-name"
    case attachment
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = EntryType(rawValue: raw) ?? .unknown
    }
}

// MARK: - Raw JSONL Entry

struct RawEntry: Codable {
    // Common fields
    let type: EntryType
    let uuid: String?
    let parentUuid: String?
    let timestamp: String?
    let sessionId: String?
    let isSidechain: Bool?
    let userType: String?
    let entrypoint: String?
    let cwd: String?
    let version: String?
    let gitBranch: String?
    let slug: String?

    // User/Assistant message
    let message: RawMessage?
    let promptId: String?
    let permissionMode: String?
    let isCompactSummary: Bool?
    let isVisibleInTranscriptOnly: Bool?
    let isMeta: Bool?
    let sourceToolAssistantUUID: String?
    let toolUseResult: ToolUseResultMeta?
    let requestId: String?
    let isApiErrorMessage: Bool?

    // System-specific
    let subtype: String?
    let durationMs: Int?
    let messageCount: Int?
    let content: AnyCodable?
    let level: String?
    let logicalParentUuid: String?
    let compactMetadata: CompactMetadata?
    let url: String?
    let upgradeNudge: String?

    // Special types
    let customTitle: String?
    let lastPrompt: String?
    let agentName: String?
    let operation: String?

    // File history
    let snapshot: FileSnapshot?
    let isSnapshotUpdate: Bool?
    let messageId: String?

    // Attachment
    let attachment: AttachmentData?

    // Progress
    let data: AnyCodable?
    let toolUseID: String?
    let parentToolUseID: String?

    // Preserved for lossless round-tripping (not decoded from JSON)
    var rawJSON: String?

    enum CodingKeys: String, CodingKey {
        case type, uuid, parentUuid, timestamp, sessionId, isSidechain
        case userType, entrypoint, cwd, version, gitBranch, slug
        case message, promptId, permissionMode
        case isCompactSummary, isVisibleInTranscriptOnly, isMeta
        case sourceToolAssistantUUID, toolUseResult, requestId, isApiErrorMessage
        case subtype, durationMs, messageCount, content, level
        case logicalParentUuid, compactMetadata, url, upgradeNudge
        case customTitle, lastPrompt, agentName, operation
        case snapshot, isSnapshotUpdate, messageId
        case attachment
        case data, toolUseID, parentToolUseID
    }
}

// MARK: - Message

struct RawMessage: Codable {
    let role: String
    let content: MessageContent

    // Assistant-only fields
    let model: String?
    let id: String?
    let type: String?
    let stopReason: String?
    let stopSequence: String?
    let stopDetails: AnyCodable?
    let usage: UsageInfo?

    enum CodingKeys: String, CodingKey {
        case role, content, model, id, type
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case stopDetails = "stop_details"
        case usage
    }
}

// MARK: - Message Content (String or Array)

enum MessageContent: Codable {
    case text(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let blocks = try container.decode([ContentBlock].self)
            self = .blocks(blocks)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

// MARK: - Content Blocks

enum ContentBlock: Codable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
    case image(ImageBlock)
    case unknown(AnyCodable)

    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()

        switch type {
        case "text":
            self = .text(try single.decode(TextBlock.self))
        case "tool_use":
            self = .toolUse(try single.decode(ToolUseBlock.self))
        case "tool_result":
            self = .toolResult(try single.decode(ToolResultBlock.self))
        case let t where t.hasPrefix("image"):
            self = .image(try single.decode(ImageBlock.self))
        default:
            self = .unknown(try single.decode(AnyCodable.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let b): try b.encode(to: encoder)
        case .toolUse(let b): try b.encode(to: encoder)
        case .toolResult(let b): try b.encode(to: encoder)
        case .image(let b): try b.encode(to: encoder)
        case .unknown(let d): try d.encode(to: encoder)
        }
    }
}

struct TextBlock: Codable {
    let type: String
    var text: String
}

struct ToolUseBlock: Codable {
    let type: String
    let id: String
    let name: String
    let input: AnyCodable
    let caller: ToolCaller?
}

struct ToolCaller: Codable {
    let type: String
}

struct ToolResultBlock: Codable {
    let type: String
    let toolUseId: String
    let content: ToolResultContent
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

enum ToolResultContent: Codable {
    case text(String)
    case blocks([ToolResultContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let blocks = try container.decode([ToolResultContentBlock].self)
            self = .blocks(blocks)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let str): try container.encode(str)
        case .blocks(let blocks): try container.encode(blocks)
        }
    }

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .blocks(let blocks): return blocks.compactMap(\.text).joined(separator: "\n")
        }
    }
}

struct ToolResultContentBlock: Codable {
    let type: String
    let text: String?
}

struct ImageBlock: Codable {
    let type: String
    let source: ImageSource
}

struct ImageSource: Codable {
    let type: String
    let data: String
}

// MARK: - Supporting Types

struct UsageInfo: Codable {
    let inputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    let outputTokens: Int?
    let serverToolUse: ServerToolUse?
    let serviceTier: String?
    let cacheCreation: CacheCreation?
    let inferenceGeo: String?
    let iterations: [AnyCodable]?
    let speed: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case serverToolUse = "server_tool_use"
        case serviceTier = "service_tier"
        case cacheCreation = "cache_creation"
        case inferenceGeo = "inference_geo"
        case iterations, speed
    }
}

struct ServerToolUse: Codable {
    let webSearchRequests: Int?
    let webFetchRequests: Int?

    enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
        case webFetchRequests = "web_fetch_requests"
    }
}

struct CacheCreation: Codable {
    let ephemeral1hInputTokens: Int?
    let ephemeral5mInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }
}

struct ToolUseResultMeta: Codable {
    let stdout: String?
    let stderr: String?
    let interrupted: Bool?
    let isImage: Bool?
    let noOutputExpected: Bool?
}

struct CompactMetadata: Codable {
    let trigger: String?
    let preTokens: Int?
    let preCompactDiscoveredTools: [String]?
}

struct FileSnapshot: Codable {
    let messageId: String?
    let trackedFileBackups: [String: FileBackup]?
    let timestamp: String?
}

struct FileBackup: Codable {
    let backupFileName: String?
    let version: Int?
    let backupTime: String?
}

struct AttachmentData: Codable {
    let type: String?
    let source: ImageSource?
}
