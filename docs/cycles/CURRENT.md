# ⚠️ Superseded — see `/ROADMAP.md`

This file reflects the state after the very first 20 build cycles, before
themes, archive, favorites, the unified export sheet, and the design overhauls.
It is no longer maintained. The current authoritative roadmap lives at
`ROADMAP.md` in the repo root.

---

# Claude Sessions — Current State (After 20 Cycles)

## Working Features
- [x] Swift Package project, builds with `swift build`, launches as macOS app
- [x] Dark mode enforced, full custom color system per spec
- [x] NavigationSplitView with sidebar + detail pane
- [x] ProjectScanner — discovers all projects from ~/.claude/projects/
- [x] Reads sessions-index.json for metadata + discovers non-indexed JSONL files
- [x] Human-readable project names from directory slugs
- [x] Sidebar with project disclosure groups, session rows, search filtering
- [x] Click-to-select sessions (explicit Button-based, not List selection)
- [x] Selection indicator bar + highlight
- [x] Dirty state indicator dot on selected session row
- [x] Full JSONL parser — all 11 entry types
- [x] Tool call <-> tool result pairing algorithm
- [x] Display message types: UserText, AssistantText, ToolInteraction, ToolCall, ToolResult, System, CompactBoundary
- [x] Conversation stats (user/claude/tool/system counts + duration)
- [x] All message views with role-colored cards and hover effects
- [x] **Markdown renderer** — headers (H1-H3), bullet lists, numbered lists, blockquotes, horizontal rules, code blocks with language label + copy button, inline formatting via AttributedString
- [x] Collapsible tool calls and results with expand/collapse
- [x] Tool-specific icons (terminal, doc, magnifyingglass, etc.)
- [x] Filter toggles (User/Claude/Tools/System) with icons
- [x] Chat/JSON mode toggle
- [x] JSON mode viewer (line numbers, type-colored dots, messages-only filter)
- [x] Copy buttons on messages (hover-revealed)
- [x] Context menus on messages (Copy, Edit, Copy Raw Markdown, Copy as Prompt)
- [x] Context menus on sidebar items (Open in Finder, Copy Session ID, Copy File Path)
- [x] **Message editing** — inline TextEditor for user/Claude messages, Done/Cancel, gold border, dirty state
- [x] **Save & backup** — BackupService with retention (20 max), ConversationWriter with lossless round-tripping, atomic writes
- [x] Cmd+S save shortcut + Save button in toolbar
- [x] Toast feedback on save
- [x] **Export as Prompt** — sheet with per-message checkboxes, 3 format options, copy to clipboard
- [x] Export button in toolbar
- [x] **Open in Claude Code** — Resume button launches terminal with `claude --resume`
- [x] **FileWatcher** — FSEvents-based live reload when files change (auto-reload if not dirty)
- [x] **AI Search** — OpenRouter integration, text search + AI search modes, search view sheet
- [x] Cmd+Shift+F search shortcut
- [x] **ClipboardService** — formatted multi-message copy
- [x] **Delete messages** — mark for deletion, track in deletedMessageIds, undelete before save
- [x] Settings (General, AI Search, Advanced) with Keychain storage
- [x] LRU conversation cache (10 entries)
- [x] Scroll to top on conversation change
- [x] Keyboard shortcuts: Cmd+J (JSON), Cmd+S (Save), Cmd+Shift+F (Search), Cmd+Shift+R (Refresh), Cmd+Shift+Y (System toggle)

## Not Yet Implemented
- [ ] Multi-select mode UI (selection toolbar, checkboxes on messages, Cmd+A)
- [ ] JSON mode editing (currently read-only)
- [ ] Light mode theme colors
- [ ] Save conflict detection (file modified externally while dirty)
- [ ] Navigate-away confirmation dialog for unsaved changes
- [ ] Conversation version history / diff view
- [ ] Tagging / bookmarking
- [ ] Unit tests

## Architecture (34 Swift files)
```
ClaudeSessions/Sources/ClaudeSessions/
├── ClaudeSessionsApp.swift      — @main, WindowGroup, Settings, Commands
├── AppState.swift               — Central ObservableObject state management
├── ContentView.swift            — NavigationSplitView root
├── Models/
│   ├── AnyCodable.swift         — Type-erased JSON wrapper
│   ├── ConversationEntry.swift  — All JSONL Codable types
│   ├── DisplayModels.swift      — UI display models
│   └── SessionIndex.swift       — sessions-index.json types
├── Services/
│   ├── AISearchService.swift    — OpenRouter search integration
│   ├── BackupService.swift      — Timestamped backup before save
│   ├── ClipboardService.swift   — Multi-message copy formatting
│   ├── ConversationParser.swift — JSONL -> Conversation with tool pairing
│   ├── ConversationWriter.swift — Lossless JSONL writer
│   └── ProjectScanner.swift     — ~/.claude/projects/ discovery
├── Utilities/
│   ├── DateFormatting.swift     — ISO8601 parse, time/date display
│   ├── FileWatcher.swift        — FSEvents file change detection
│   ├── KeychainService.swift    — Secure API key storage
│   ├── ProcessLauncher.swift    — Terminal launch via AppleScript
│   └── Theme.swift              — Color system (dark mode)
└── Views/
    ├── Conversation/            — 12 view files
    ├── JSONMode/                — 1 view file
    ├── Search/                  — 1 view file
    ├── Settings/                — 1 view file
    ├── Shared/                  — 2 view files
    ├── Sidebar/                 — 2 view files
    └── Toolbar/                 — 1 view file
```

## Design Decisions
- Swift Package instead of Xcode project — CLI-buildable, no .xcodeproj to manage
- Zero external dependencies — pure Swift + system frameworks
- Lossless round-tripping: rawJSON per entry, only re-serialize modified
- File order display (not parentUuid threading)
- LRU cache with 10-conversation limit
- FSEvents for live reload
- Dark mode as primary design target
- Explicit Button-based selection (not List selection binding)
