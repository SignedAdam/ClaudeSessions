# Feature Specifications — Detailed

## F1: Conversation Discovery & Loading

### Discovery
The `ProjectScanner` service scans `~/.claude/projects/` on app launch:

1. List all directories in `~/.claude/projects/`
2. For each directory:
   a. Read `sessions-index.json` if it exists → extract summaries, dates, message counts
   b. Scan for `*.jsonl` files at the root level of the directory
   c. For JSONL files NOT in the index, extract minimal metadata: file size, modification date, and the first user text message (read first ~50 lines, find first `type: "user"` with string content, extract first 80 characters)
   d. Convert the directory slug to a human-readable project name:
      - `-Users-sauel-dev-shortimize-backend` → `shortimize-backend`
      - `-Users-sauel-dev` → `dev`
      - `-Users-sauel` → `~ (home)`
      - Rule: take the last path component from `originalPath` in the index, or strip the common prefix from the slug
3. Build a `[Project]` array, each containing its `[SessionInfo]` entries
4. Sort projects alphabetically by name
5. Sort sessions within each project by modified date (newest first)

### Loading
When the user selects a session:

1. Read the entire JSONL file into memory (even 4MB files are trivial for in-memory processing)
2. Parse each line as JSON into `ConversationEntry` (the raw Codable type)
3. Run `ConversationParser.parse(entries:)` to produce a `Conversation`:
   - Filter to message-relevant entries (user, assistant, system with interesting subtypes)
   - Build the display list: extract text, tool calls, tool results into `DisplayMessage` structs
   - Identify compact boundaries and flag them
   - Compute stats (counts per type, first/last timestamp, duration)
4. Set the `ConversationViewModel.conversation` which triggers the view to render

### Caching
- Parsed `Conversation` objects are cached in a dictionary keyed by session ID
- Cache is invalidated when the file's modification date changes (checked on each selection)
- Maximum 10 conversations cached in memory (LRU eviction)

## F2: Message Rendering

### User Messages
- Blue-tinted card
- Header: "Adam" (configurable display name), timestamp, copy button
- Body: plain text (no markdown for user messages — render as-is with line breaks preserved)
- Compact summary messages: different style — gray background, italic, collapsible, prefixed with "Context Summary" label

### Claude Messages
- Purple-tinted card
- Header: "Claude", model tag (e.g., "opus-4-6"), timestamp, copy button
- Body: rendered markdown using `AttributedString` with markdown parsing:
  - Headers (H1, H2, H3) with appropriate sizing and weight
  - **Bold**, *italic*, ***bold italic***
  - `inline code` with monospace font and subtle background
  - Code blocks with syntax region background and monospace font
  - Bullet lists, numbered lists
  - Blockquotes with left border and muted color
  - Links (clickable, opens in default browser)
  - Tables (basic support)
- API error messages (`isApiErrorMessage: true`): red-tinted background, "API Error" label

### Tool Calls
- Green-tinted card, compact
- Header: "Tool: <ToolName>" + description if available, timestamp
- Body: collapsible section. Collapsed by default.
  - Collapsed: shows a 1-line summary of the most relevant input field:
    - Bash: the `command` value
    - Read/Write/Edit: the `file_path`
    - Grep/Glob: the `pattern`
    - Agent: the `description`
  - Expanded: shows full `input` as formatted JSON

### Tool Results
- Green-tinted card, compact
- Header: "Result" (or "Result (error)" if `is_error`), timestamp
- Body: collapsible section. Collapsed by default.
  - Collapsed: first ~100 characters of the result text on one line
  - Expanded: full result text, monospace font, scroll if long (max height 400px)

### System Messages
- Orange-tinted card, compact, only shown when System filter is enabled
- Render subtypes differently:
  - `turn_duration`: "Turn took Xs, N messages"
  - `local_command`: show the command name
  - `compact_boundary`: "Conversation compacted (182K tokens → compressed)"
  - `bridge_status`: show the URL

### Visual Grouping
Tool calls and their results should be visually associated. When a tool_use block is followed by a tool_result that matches its `tool_use_id`, render them as a single grouped block:

```
┌─ Tool: Bash — ls -la ──── 5:03 PM ──────┐
│ ▶ ls -la /Users/sauel/dev               │
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
│ ▶ total 128 drwxr-xr-x 24 sauel...      │
└──────────────────────────────────────────┘
```

This is achieved by the parser: consecutive tool_use + matching tool_result are merged into a `ToolInteraction` display item.

## F3: Copy System

### Single Message Copy
- Copy button in each message header (SF Symbol: `doc.on.doc`)
- On click: copies the message text to clipboard with role and timestamp
- Button shows checkmark for 1.5 seconds as feedback
- Format:
```
[Adam — 5:02 PM]
the user's message text
```

### Multi-Select Copy
Detailed in UX spec. Format when copying multiple messages:
```
[Adam — 5:02 PM]
first message

[Claude — 5:03 PM]
response text

[Tool: Bash — 5:03 PM]
ls -la /dev

[Result — 5:03 PM]
total 128...
```

Each message separated by a blank line. Tool calls show the primary input value. Tool results show the result text.

### Copy Raw Markdown (Claude messages only)
Right-click → "Copy Raw Markdown" copies the original markdown text without any rendering/processing. Useful for pasting into other markdown contexts.

## F4: Message Editing

### Edit Flow
1. User clicks pencil icon (or right-click → Edit, or Cmd+E on focused message)
2. The message body transitions to an editable `TextEditor`
3. For user messages: edit the plain text
4. For Claude messages: edit the raw markdown source
5. Two buttons appear: "Done" and "Cancel"
6. "Done" commits the edit to the in-memory model, marks `isDirty = true`
7. "Cancel" reverts
8. Only one message editable at a time. Starting an edit on another message auto-commits the current one.
9. Tool calls and results cannot be edited in chat mode (edit them in JSON mode)

### Dirty State
When `isDirty = true`:
- The toolbar shows an amber "Unsaved Changes" badge
- The session row in the sidebar shows an orange dot
- A "Save" button appears in the toolbar
- Navigating to another session triggers: "You have unsaved changes. Save / Discard / Cancel"

### Save Flow
1. User clicks "Save" (or Cmd+S)
2. `BackupService.backup(sessionId:)` copies the original file to the backup directory
3. `ConversationWriter.write(conversation:, to: filePath)` serializes the modified conversation:
   - For each entry in the original JSONL, if the message was edited, update the content field
   - If messages were deleted, omit those entries (and their associated tool results / file snapshots)
   - Preserve all other entries exactly as they were (don't touch what wasn't changed)
4. Write the new JSONL to a temp file, then atomic-rename to the original path
5. Clear `isDirty`, update cache
6. Show toast: "Saved"

### Delete Messages
- Right-click → "Delete Message" marks a message for deletion (strikethrough + muted opacity)
- Deleted messages are excluded from the JSONL on save
- When deleting a tool_use, also mark its corresponding tool_result for deletion
- "Undo Delete" option on deleted messages (before save)

## F5: JSON Mode

### View
- Toggle via toolbar button or `Cmd+J`
- Shows the raw JSONL file content in a monospace `TextEditor`
- Each JSON line is on its own line
- Optionally syntax highlighted (JSON keys in one color, strings in another, numbers in a third)
- Filter toggle: "Show all" vs "Messages only" (hides file-history-snapshot, progress, queue-operation)

### Edit
- User can edit any JSON content directly
- Validation: on save attempt, each line is parsed as JSON. Lines that fail to parse are highlighted red.
- Same save flow as chat mode (backup → write → verify)

### Relationship to Chat Mode
- Edits in chat mode are reflected in JSON mode and vice versa
- If the user edits in JSON mode in a way that changes message content, switching back to chat mode shows the updated content
- The source of truth is the in-memory `[ConversationEntry]` array. Both views read from and write to it.

## F6: Export as Prompt

### Purpose
Extract just the human-Claude dialogue — no tool calls, no system messages, no compact summaries — formatted for pasting into a new Claude session to continue a conversation or provide context.

### UI
1. User clicks "Export as Prompt" in the toolbar
2. A sheet opens showing a preview of the extracted conversation
3. Each message has a checkbox (checked by default) to include/exclude it
4. The preview updates live as messages are toggled
5. Format options (radio buttons):
   - **Labeled** (default): `[User]` / `[Claude]` prefixes
   - **Bare**: just the text with separators
   - **Markdown**: full markdown with `---` separators

### Format (Labeled)
```
[User]
What about modafinil combined with methylene blue?

[Claude]
Here's the core mechanism...

[User]
What about cold exposure?

[Claude]
For your specific profile...
```

### Actions at Bottom of Sheet
- "Copy to Clipboard" — copies the formatted text
- "Save as .txt" — save dialog
- "Start New Claude Session" — writes to temp file and opens Claude Code (see F8)

## F7: AI Search

### Overview
Natural language search across all conversations. Uses OpenRouter API with a user-provided key.

### How It Works
1. User opens the AI search panel (Cmd+Shift+F or toolbar button)
2. Types a natural language query: "That conversation where I talked about tyramine and cheese"
3. The app:
   a. Collects the first user message + summary from each conversation (lightweight, from cache/index)
   b. Sends a request to the configured OpenRouter model with a system prompt:
   
   ```
   You are a search assistant. Given a list of conversation summaries and the user's search query, return the IDs of conversations that are most likely to match, ranked by relevance. Return ONLY a JSON array of session IDs.
   ```
   
   c. The user message contains the query + the list of `{sessionId, summary, firstPrompt, date}` objects
   d. Parse the response to get ranked session IDs
   e. Display matching conversations in order

4. Clicking a search result navigates to that conversation

### Deep Search (v1.1 — stretch goal)
For more precise queries, the app can search within conversation content:
- Load the full text of top candidate conversations
- Send each to the model asking "Does this conversation contain information about X? If so, quote the relevant section."
- Display results with the relevant excerpt highlighted

### Configuration
- API key stored in macOS Keychain
- Model selection: free text field with common presets
- Max tokens: configurable (default 4096)

## F8: Open in Claude Code

### "Continue in Claude Code" Action
1. User clicks "Open in Claude Code" in the toolbar
2. The app resolves the original project path from the conversation metadata (`cwd` field)
3. Launches a terminal command:
   ```
   cd <project-path> && claude --resume <session-id>
   ```
4. This opens Claude Code CLI and resumes the session

### "Start Fresh from Exported Prompt"
1. From the Export as Prompt sheet, user clicks "Start New Claude Session"
2. The app writes the exported text to a temp file
3. Launches:
   ```
   cd <project-path> && claude < <temp-file>
   ```
4. Or uses the clipboard and tells the user to paste it

### Implementation
Use `Process` (Foundation) to launch the command. Detect terminal app (Terminal.app or iTerm2 or Warp) and open the command in a new window/tab.

## F9: Automatic Backup

### Trigger
Every save operation triggers a backup of the original file first.

### Location
```
~/.claude-sessions-backups/
  <session-id>/
    2026-04-05T17-30-00.jsonl    # timestamp in filename
    2026-04-05T18-45-12.jsonl
```

### Retention
- Keep last 20 backups per session
- Older backups are auto-deleted (FIFO)

### Restore
v1: Manual. User navigates to the backup directory and copies the file back.
Future: In-app restore with diff view.

## F10: Right-Click Context Menus

Implemented using SwiftUI `.contextMenu` modifier on each message view. See UX spec for full menu items per message type.

Additional global context menu items (right-click on sidebar session row):
- Open in Finder
- Copy Session ID
- Copy File Path
- Delete Session (with confirmation — moves to Trash)
