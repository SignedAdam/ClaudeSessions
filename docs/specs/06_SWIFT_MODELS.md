# Swift Data Models

All models use `Codable` for JSON serialization. Enums use `String` raw values for type discrimination.

## Core JSONL Entry Types

```swift
import Foundation

// MARK: - Raw JSONL Entry (one line in the file)

/// The top-level discriminator. Each line in the JSONL is decoded as this first,
/// then the appropriate sub-model is extracted based on `type`.
struct RawEntry: Codable, Identifiable {
    let id: UUID  // computed from `uuid` field, or generated for entries without one
    
    // Common fields (present on most entries)
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
    
    // Type-specific fields
    let subtype: String?
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
    let durationMs: Int?
    let messageCount: Int?
    let content: AnyCodable?  // String or structured
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
    
    // The original raw JSON string (preserved for lossless round-tripping)
    var rawJSON: String?
}

enum EntryType: String, Codable {
    case user
    case assistant
    case system
    case fileHistorySnapshot = "file-history-snapshot"
    case progress
    case queueOperation = "queue-operation"
    case lastPrompt = "last-prompt"
    case customTitle = "custom-title"
    case permissionModeEntry = "permission-mode"  // avoid conflict with field name
    case agentNameEntry = "agent-name"
    case attachment
    case unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = EntryType(rawValue: raw) ?? .unknown
    }
}
```

## Message Content Types

```swift
// MARK: - Message wrapper

/// The `message` field on user and assistant entries.
struct RawMessage: Codable {
    let role: String  // "user" or "assistant"
    let content: MessageContent
    
    // Assistant-only fields
    let model: String?
    let id: String?        // API message ID (msg_...)
    let type: String?      // "message"
    let stopReason: String?
    let stopSequence: String?
    let usage: UsageInfo?
    
    enum CodingKeys: String, CodingKey {
        case role, content, model, id, type
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

/// Content can be a String (user text) or an Array of content blocks (tool results, assistant content)
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

/// A single block within an assistant message's content array,
/// or a tool_result block within a user message's content array.
enum ContentBlock: Codable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
    case image(ImageBlock)
    case unknown(AnyCodable)
    
    // Discriminated on the `type` field
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        let singleContainer = try decoder.singleValueContainer()
        switch type {
        case "text":
            self = .text(try singleContainer.decode(TextBlock.self))
        case "tool_use":
            self = .toolUse(try singleContainer.decode(ToolUseBlock.self))
        case "tool_result":
            self = .toolResult(try singleContainer.decode(ToolResultBlock.self))
        case let t where t.starts(with: "image"):
            self = .image(try singleContainer.decode(ImageBlock.self))
        default:
            self = .unknown(try singleContainer.decode(AnyCodable.self))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let block): try block.encode(to: encoder)
        case .toolUse(let block): try block.encode(to: encoder)
        case .toolResult(let block): try block.encode(to: encoder)
        case .image(let block): try block.encode(to: encoder)
        case .unknown(let data): try data.encode(to: encoder)
        }
    }
}

struct TextBlock: Codable {
    let type: String  // always "text"
    var text: String   // mutable for editing
}

struct ToolUseBlock: Codable {
    let type: String  // always "tool_use"
    let id: String
    let name: String
    let input: AnyCodable
    let caller: ToolCaller?
}

struct ToolCaller: Codable {
    let type: String
}

struct ToolResultBlock: Codable {
    let type: String  // always "tool_result"
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

/// Tool result content can be a String or an Array of content blocks
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
}

struct ToolResultContentBlock: Codable {
    let type: String
    let text: String?
}

struct ImageBlock: Codable {
    let type: String  // "image/jpeg", "image/png", etc.
    let source: ImageSource
}

struct ImageSource: Codable {
    let type: String  // "base64"
    let data: String
}
```

## Supporting Types

```swift
// MARK: - Usage Info

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
```

## Display Models (Parsed, for UI)

```swift
// MARK: - Display Models

/// A project containing multiple conversation sessions.
struct Project: Identifiable {
    let id: String                    // directory slug
    let name: String                  // human-readable name
    let originalPath: String          // full filesystem path
    var sessions: [SessionInfo]
}

/// Lightweight session metadata (for sidebar display).
struct SessionInfo: Identifiable {
    let id: String                    // session UUID
    let filePath: String              // full path to .jsonl file
    let title: String                 // summary or first prompt preview
    let firstPrompt: String?          // first user message text
    let messageCount: Int
    let created: Date
    let modified: Date
    let gitBranch: String?
    let projectPath: String?
    let isFromIndex: Bool             // whether this came from sessions-index.json
}

/// A fully parsed conversation ready for display.
struct Conversation {
    let sessionId: String
    let filePath: String
    var displayMessages: [DisplayMessage]
    var rawEntries: [RawEntry]        // for JSON mode and lossless round-tripping
    var stats: ConversationStats
    var isDirty: Bool = false
    var deletedIndices: Set<Int> = [] // indices into rawEntries marked for deletion
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

/// A single item in the display list. This is what the UI renders.
enum DisplayMessage: Identifiable {
    case userText(UserTextMessage)
    case assistantText(AssistantTextMessage)
    case toolInteraction(ToolInteraction)     // grouped tool_use + tool_result
    case toolCall(ToolCallMessage)            // standalone tool_use (no matching result yet)
    case toolResult(ToolResultMessage)        // standalone tool_result
    case systemMessage(SystemDisplayMessage)
    case compactBoundary(CompactBoundaryMessage)
    
    var id: String { /* return the uuid from the underlying struct */ }
    var timestamp: Date? { /* return the timestamp from the underlying struct */ }
    var entryIndex: Int { /* index into rawEntries for editing/deletion */ }
}

struct UserTextMessage: Identifiable {
    let id: String
    var text: String                   // mutable for editing
    let timestamp: Date?
    let isCompactSummary: Bool
    let entryIndex: Int                // index into Conversation.rawEntries
}

struct AssistantTextMessage: Identifiable {
    let id: String
    var text: String                   // mutable for editing
    let timestamp: Date?
    let model: String?
    let isApiError: Bool
    let tokenUsage: UsageInfo?
    let entryIndex: Int
    let blockIndex: Int                // index into the content blocks array
}

struct ToolInteraction: Identifiable {
    let id: String
    let toolCall: ToolCallMessage
    let toolResult: ToolResultMessage?
}

struct ToolCallMessage: Identifiable {
    let id: String                     // tool_use block id
    let toolName: String
    let input: [String: AnyCodable]
    let description: String?           // input.description if present
    let summary: String                // primary input field for display
    let timestamp: Date?
    let entryIndex: Int
}

struct ToolResultMessage: Identifiable {
    let id: String                     // generated, or tool_use_id
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
```

## AnyCodable Helper

```swift
/// Type-erased Codable wrapper for arbitrary JSON values.
/// Used for tool inputs, progress data, and other flexible fields.
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) { self.value = value }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Sessions Index

struct SessionsIndex: Codable {
    let version: Int
    let originalPath: String?
    let entries: [SessionsIndexEntry]
}

struct SessionsIndexEntry: Codable {
    let sessionId: String
    let fullPath: String
    let fileMtime: Int64?
    let firstPrompt: String?
    let summary: String?
    let messageCount: Int?
    let created: String?
    let modified: String?
    let gitBranch: String?
    let projectPath: String?
    let isSidechain: Bool?
}
```

## Important Implementation Notes

1. **Lossless round-tripping:** When saving, we MUST preserve the original JSON for entries that weren't modified. The approach: store the raw JSON string (`rawJSON`) for each entry on parse. On write, only re-serialize entries that were modified. Unmodified entries write their `rawJSON` verbatim.

2. **Flexible decoding:** Many fields are optional. Use `decodeIfPresent` everywhere. Unknown entry types should be preserved as-is.

3. **The `entryIndex`** on display models maps back to the position in `Conversation.rawEntries`, enabling edits to be written back to the correct JSONL line.

4. **The `blockIndex`** on `AssistantTextMessage` maps to the position within the `message.content` array, since a single assistant entry can contain multiple text blocks.
