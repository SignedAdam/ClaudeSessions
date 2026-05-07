# Architecture

## Technology

- **SwiftUI** for all views
- **AppKit** integration for: context menus, `NSPasteboard`, launching external processes, window management
- **Swift Concurrency** (`async/await`, `@MainActor`) for all async work
- **No external dependencies.** Pure Swift + system frameworks. No SPM packages.
- **Target:** macOS 14.0+ (Sonoma)

## App Structure

```
ClaudeSessions/
├── ClaudeSessionsApp.swift          # @main, WindowGroup
├── Models/
│   ├── ConversationEntry.swift       # Codable types for JSONL entries
│   ├── Conversation.swift            # Parsed conversation (entries → messages)
│   ├── Project.swift                 # Project grouping (dir → sessions)
│   ├── SessionIndex.swift            # sessions-index.json Codable
│   └── MessageBlock.swift            # Content blocks (text, tool_use, tool_result)
├── Services/
│   ├── ConversationStore.swift       # Discovery, loading, caching of conversations
│   ├── ConversationParser.swift      # JSONL → Conversation conversion
│   ├── ConversationWriter.swift      # Writes modified conversations back to JSONL
│   ├── BackupService.swift           # Auto-backup before saves
│   ├── ProjectScanner.swift          # Scans ~/.claude/projects/ for project dirs
│   ├── AISearchService.swift         # OpenRouter integration for AI search
│   └── ClipboardService.swift        # Copy formatting
├── ViewModels/
│   ├── SidebarViewModel.swift        # Project list + session list state
│   ├── ConversationViewModel.swift   # Currently viewed conversation state
│   ├── EditorViewModel.swift         # Edit mode state, dirty tracking, save
│   └── SearchViewModel.swift         # Search state (text + AI)
├── Views/
│   ├── Sidebar/
│   │   ├── SidebarView.swift         # Left panel: projects + sessions
│   │   ├── ProjectRow.swift          # Single project in sidebar
│   │   └── SessionRow.swift          # Single session in sidebar
│   ├── Conversation/
│   │   ├── ConversationView.swift    # Main chat view (ScrollView of messages)
│   │   ├── MessageView.swift         # Single message bubble
│   │   ├── UserMessageView.swift     # User message styling
│   │   ├── AssistantMessageView.swift# Claude message styling
│   │   ├── ToolCallView.swift        # Collapsible tool call display
│   │   ├── ToolResultView.swift      # Collapsible tool result display
│   │   ├── SystemMessageView.swift   # System message display
│   │   ├── MessageEditor.swift       # Inline text editor for editing messages
│   │   └── MarkdownRenderer.swift    # Markdown → AttributedString
│   ├── Toolbar/
│   │   ├── ConversationToolbar.swift # Top bar: filters, actions
│   │   ├── FilterToggles.swift       # Message type toggles
│   │   └── SelectionToolbar.swift    # Multi-select actions bar
│   ├── JSONMode/
│   │   ├── JSONEditorView.swift      # Raw JSONL editor
│   │   └── JSONEntryRow.swift        # Single JSONL line in raw mode
│   ├── Search/
│   │   ├── SearchView.swift          # Search panel (text + AI)
│   │   └── SearchResultRow.swift     # Single search result
│   ├── Settings/
│   │   └── SettingsView.swift        # Preferences: API key, theme, etc.
│   └── Shared/
│       ├── CopyButton.swift          # Reusable copy button with feedback
│       └── ToastView.swift           # Brief feedback overlay
└── Utilities/
    ├── DateFormatting.swift           # Timestamp formatting helpers
    ├── FileWatcher.swift             # FSEvents watcher for live updates
    └── ProcessLauncher.swift         # Launch Claude Code CLI
```

## Data Flow

```
~/.claude/projects/
        │
        ▼
  ProjectScanner          ── scans dirs, finds JSONL files + sessions-index.json
        │
        ▼
  ConversationStore       ── lazy-loads conversations, caches parsed results
        │
        ▼
  ConversationParser      ── reads JSONL lines, produces Conversation model
        │
        ▼
  ConversationViewModel   ── holds current conversation, filter state, selection
        │
        ▼
  ConversationView        ── renders messages, handles interactions
        │
        ▼ (on edit + save)
  ConversationWriter      ── serializes modified Conversation back to JSONL
        │
        ▼ (before write)
  BackupService           ── copies original file to backup location
```

## Key Design Decisions

### 1. Lazy Loading
Conversations are not loaded until the user selects them. The sidebar shows metadata from `sessions-index.json` or lightweight file stat info (size, date) for non-indexed sessions. The first user text message is extracted only on demand for preview.

### 2. In-Memory Editing
When editing, the app works on an in-memory copy of the parsed `Conversation`. Changes are tracked via a `isDirty` flag. Nothing touches disk until the user explicitly clicks "Save." If the user navigates away with unsaved changes, they get a confirmation dialog.

### 3. Backup Before Save
The `BackupService` copies the original JSONL to `~/.claude-sessions-backups/<session-id>/<timestamp>.jsonl` before any write. This is automatic and non-optional.

### 4. No Database
No SQLite, no Core Data. All data lives in the JSONL files on disk. The app reads from them and writes back to them. Conversation discovery happens via filesystem scanning. This keeps the architecture simple and the app stateless — you can delete it and lose nothing.

### 5. AI Search is Optional
The AI search feature requires an OpenRouter API key. Without it, the app still provides full-text search across conversations. The AI feature is an enhancement that uses a configured model to intelligently find conversations matching a natural language query.

## Window Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ ◉ ◉ ◉  Claude Sessions                               ⚙ Search │
├────────────┬─────────────────────────────────────────────────────┤
│ Projects   │  [Toolbar: filters | select | json | actions]      │
│            │─────────────────────────────────────────────────────│
│ ▼ dev      │                                                    │
│   session1 │  ┌─ User ──────────────── 5:02 PM ──────── [📋] ─┐│
│   session2 │  │ message text here                              ││
│ ▼ shortim  │  └────────────────────────────────────────────────┘│
│   session3 │                                                    │
│   ...      │  ┌─ Claude ─── opus-4-6 ── 5:03 PM ──── [📋] ───┐│
│            │  │ ## Response                                    ││
│            │  │ response text with **markdown** here           ││
│            │  └────────────────────────────────────────────────┘│
│            │                                                    │
│            │  ┌─ Tool: Bash ───────────── 5:03 PM ────────────┐│
│            │  │ ▶ ls -la /Users/alice/dev                     ││
│            │  └────────────────────────────────────────────────┘│
│            │                                                    │
│            │  ┌─ Result ──────────────── 5:03 PM ─────────────┐│
│            │  │ ▶ total 128 drwxr-xr-x 24 alice staff...     ││
│            │  └────────────────────────────────────────────────┘│
│            │                                                    │
├────────────┴─────────────────────────────────────────────────────┤
│ User: 12 │ Claude: 11 │ Tools: 34 │ Duration: 1h 23m           │
└──────────────────────────────────────────────────────────────────┘
```
