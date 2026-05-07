# Data Model — JSONL Format Reference

## File Location

Claude Code stores conversations under:
```
~/.claude/projects/<project-dir-slug>/
```

Where `<project-dir-slug>` is the working directory path with `/` replaced by `-`. Examples:
- `/Users/alice/dev` → `-Users-alice-dev`
- `/Users/alice/dev/shortimize-backend` → `-Users-alice-dev-shortimize-backend`

Each project directory contains:
- `<session-uuid>.jsonl` — conversation files (one per session)
- `<session-uuid>/subagents/agent-<id>.jsonl` — subagent conversation files
- `sessions-index.json` — optional index with summaries (not all projects have this, not all sessions are indexed)
- `memory/` — project memory files (not relevant to this app)

## sessions-index.json Structure

```json
{
  "version": 1,
  "originalPath": "/Users/alice/dev",
  "entries": [
    {
      "sessionId": "722e20c8-...",
      "fullPath": "/Users/alice/.claude/projects/-Users-alice-dev/722e20c8-....jsonl",
      "fileMtime": 1769189617091,
      "firstPrompt": "Hello Claude...",
      "summary": "Short Title Here",           // may be absent
      "messageCount": 54,
      "created": "2026-01-23T17:33:36.690Z",
      "modified": "2026-01-23T22:09:45.511Z",
      "gitBranch": "main",
      "projectPath": "/Users/alice/dev",
      "isSidechain": false
    }
  ]
}
```

**Important:** Not all conversations appear in the index. The app MUST also discover conversations by scanning for `*.jsonl` files directly. The index is a supplemental data source for summaries and first-prompt previews.

## JSONL Entry Types

Each line in a `.jsonl` file is a JSON object. The `type` field determines the entry kind.

### 1. `type: "user"` — User Messages

Two variants:

#### 1a. Text message (human typed)
```json
{
  "parentUuid": "uuid-of-previous-message" | null,
  "isSidechain": false,
  "promptId": "uuid",
  "type": "user",
  "message": {
    "role": "user",
    "content": "the user's text message as a string"
  },
  "uuid": "this-message-uuid",
  "timestamp": "2026-04-01T17:02:56.500Z",
  "permissionMode": "default",
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "/Users/alice/dev",
  "sessionId": "session-uuid",
  "version": "2.1.89",
  "gitBranch": "HEAD"
}
```

Optional fields on user text messages:
- `isCompactSummary: true` — this is a conversation compaction summary, not a real user message
- `isVisibleInTranscriptOnly: true` — marks compact summaries
- `isMeta: true/false/null`

#### 1b. Tool result message
```json
{
  "parentUuid": "uuid",
  "isSidechain": false,
  "promptId": "uuid",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_01Rz6...",
        "type": "tool_result",
        "content": "stdout text or result string",
        "is_error": false
      }
    ]
  },
  "uuid": "uuid",
  "timestamp": "...",
  "toolUseResult": {
    "stdout": "...",
    "stderr": "...",
    "interrupted": false,
    "isImage": false,
    "noOutputExpected": false
  },
  "sourceToolAssistantUUID": "uuid-of-assistant-that-made-the-tool-call",
  ...common fields...
}
```

**How to distinguish:** If `message.content` is a `String`, it's a user text message. If it's an `Array`, it's a tool result.

### 2. `type: "assistant"` — Claude's Messages

```json
{
  "parentUuid": "uuid",
  "isSidechain": false,
  "message": {
    "model": "claude-opus-4-6",
    "id": "msg_012koG...",
    "type": "message",
    "role": "assistant",
    "content": [ ...content blocks... ],
    "stop_reason": "end_turn" | "tool_use",
    "stop_sequence": null,
    "stop_details": null,
    "usage": {
      "input_tokens": 3,
      "cache_creation_input_tokens": 4402,
      "cache_read_input_tokens": 11260,
      "output_tokens": 1364,
      "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
      "service_tier": "standard",
      "cache_creation": { "ephemeral_1h_input_tokens": 4402, "ephemeral_5m_input_tokens": 0 },
      "inference_geo": "",
      "iterations": [],
      "speed": "standard"
    }
  },
  "requestId": "req_011CZd...",
  "type": "assistant",
  "uuid": "uuid",
  "timestamp": "...",
  ...common fields...
}
```

Optional field:
- `isApiErrorMessage: true` — indicates this is an error from the API, not a real response

#### Content Block Types

**Text block:**
```json
{ "type": "text", "text": "markdown content here" }
```

**Tool use block:**
```json
{
  "type": "tool_use",
  "id": "toolu_01Rz6...",
  "name": "Bash",
  "input": {
    "command": "ls -la",
    "description": "List files"
  },
  "caller": { "type": "direct" }
}
```

Tool names observed: `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Agent`, `TaskCreate`, `TaskUpdate`, `TaskOutput`, `ToolSearch`, `WebSearch`, `ExitPlanMode`

Each tool has different `input` fields:
- **Bash**: `command`, `description`, `timeout`, `run_in_background`
- **Read**: `file_path`, `offset`, `limit`
- **Write**: `file_path`, `content`
- **Edit**: `file_path`, `old_string`, `new_string`, `replace_all`
- **Glob**: `pattern`, `path`
- **Grep**: `pattern`, `path`, `glob`, `output_mode`, `-i`, `-n`, etc.
- **Agent**: `description`, `prompt`, `subagent_type`, `model`, `run_in_background`
- **TaskCreate**: `subject`, `description`
- **TaskUpdate**: `id`, `status`

### 3. `type: "system"` — System Messages

Always has a `subtype` field:

#### `subtype: "turn_duration"`
```json
{
  "type": "system", "subtype": "turn_duration",
  "durationMs": 36068,
  "messageCount": 2,
  "parentUuid": "uuid", "uuid": "uuid",
  "timestamp": "...", "isMeta": false,
  ...common fields...
}
```

#### `subtype: "local_command"`
Slash commands the user ran (like `/usage`):
```json
{
  "type": "system", "subtype": "local_command",
  "content": "<command-name>/usage</command-name>\n<command-message>usage</command-message>\n<command-args></command-args>",
  "level": "info",
  ...
}
```

#### `subtype: "compact_boundary"`
Marks where conversation was auto-compacted:
```json
{
  "type": "system", "subtype": "compact_boundary",
  "content": "Conversation compacted",
  "logicalParentUuid": "uuid-before-compaction",
  "compactMetadata": {
    "trigger": "auto",
    "preTokens": 182107,
    "preCompactDiscoveredTools": ["TaskCreate"]
  },
  ...
}
```

#### `subtype: "bridge_status"`
Remote control session links:
```json
{
  "type": "system", "subtype": "bridge_status",
  "content": "/remote-control is active...",
  "url": "https://claude.ai/code/session_...",
  "upgradeNudge": "...",
  ...
}
```

### 4. `type: "file-history-snapshot"`

File version tracking. NOT a conversation message — metadata only.
```json
{
  "type": "file-history-snapshot",
  "messageId": "uuid",
  "isSnapshotUpdate": false,
  "snapshot": {
    "messageId": "uuid",
    "trackedFileBackups": {
      "path/to/file.md": {
        "backupFileName": "hash@v2",
        "version": 2,
        "backupTime": "..."
      }
    },
    "timestamp": "..."
  }
}
```

### 5. `type: "progress"`

Real-time tool execution progress. NOT a conversation message.
```json
{
  "type": "progress",
  "data": { "type": "bash_progress", "content": "..." },
  "toolUseID": "toolu_...",
  "parentToolUseID": null,
  "parentUuid": "uuid",
  ...
}
```

### 6. `type: "queue-operation"`

Message queue operations (enqueue/dequeue/remove):
```json
{
  "type": "queue-operation",
  "operation": "enqueue" | "dequeue" | "remove",
  "timestamp": "...",
  "sessionId": "...",
  "content": "queued message text"    // only on enqueue
}
```

### 7. `type: "last-prompt"`
```json
{
  "type": "last-prompt",
  "lastPrompt": "the last thing the user typed",
  "sessionId": "..."
}
```

### 8. `type: "custom-title"`
```json
{
  "type": "custom-title",
  "customTitle": "Title set by user",
  "sessionId": "..."
}
```

### 9. `type: "permission-mode"`
```json
{
  "type": "permission-mode",
  "permissionMode": "default",
  "sessionId": "..."
}
```

### 10. `type: "agent-name"`
```json
{
  "type": "agent-name",
  "agentName": "...",
  "sessionId": "..."
}
```

### 11. `type: "attachment"`

File attachments (screenshots, etc.):
```json
{
  "type": "attachment",
  "attachment": {
    "type": "image/png",
    "source": { "type": "base64", "data": "..." }
  },
  "parentUuid": "uuid",
  ...
}
```

## Message Threading

Messages form a linked list via `parentUuid`:
- Root messages have `parentUuid: null`
- Each subsequent message points to the previous one
- `isSidechain: true` marks subagent conversations
- `promptId` groups a user prompt with its responses within a turn
- `sourceToolAssistantUUID` on tool results points back to the assistant message that initiated the tool call

## Common Fields (present on most entry types)

| Field | Type | Description |
|-------|------|-------------|
| `uuid` | String | Unique ID for this entry |
| `parentUuid` | String? | UUID of the previous entry in the thread |
| `timestamp` | String | ISO 8601 timestamp |
| `sessionId` | String | Session UUID (matches filename) |
| `type` | String | Entry type discriminator |
| `isSidechain` | Bool | Whether this is a subagent message |
| `userType` | String | Always "external" for CLI usage |
| `entrypoint` | String | "cli" |
| `cwd` | String | Working directory at time of message |
| `version` | String | Claude Code version |
| `gitBranch` | String | Current git branch |
| `slug` | String? | Human-readable slug for some entries |
