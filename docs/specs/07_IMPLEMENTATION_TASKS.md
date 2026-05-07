# Implementation Tasks

Ordered for incremental progress. Each task builds on the previous ones. After each task, the app should compile and be testable.

---

## Task 1: Xcode Project & App Shell

**Objective:** Create the Xcode project and minimal app structure.

**Deliverables:**
- New SwiftUI macOS app project named `ClaudeSessions`
- Target: macOS 14.0+
- App uses `NavigationSplitView` with a sidebar and detail pane
- Sidebar shows placeholder "Projects" text
- Detail shows placeholder "Select a conversation" text
- Window minimum size: 800x500, default 1100x700
- App icon: placeholder (can be the default SwiftUI icon)
- Directory structure from `03_ARCHITECTURE.md` created with empty files

**Acceptance:**
- [ ] App compiles and launches
- [ ] Shows a split view with sidebar and detail
- [ ] Window respects minimum size

---

## Task 2: Data Models

**Objective:** Implement all Codable data models from `06_SWIFT_MODELS.md`.

**Deliverables:**
- All types from `06_SWIFT_MODELS.md` implemented
- `AnyCodable` helper working with encode/decode
- Unit tests: decode a sample JSONL line for each entry type (user text, user tool_result, assistant with text, assistant with tool_use, system/turn_duration, file-history-snapshot, queue-operation)
- Test: round-trip encode/decode preserves data

**Acceptance:**
- [ ] All model files compile
- [ ] Unit tests pass for each entry type
- [ ] Round-trip test passes

---

## Task 3: Conversation Parser

**Objective:** Implement `ConversationParser` that reads a JSONL file and produces a `Conversation`.

**Deliverables:**
- `ConversationParser.parse(data: Data) -> Conversation`
  - Reads JSONL line by line
  - Decodes each line into `RawEntry`, preserving `rawJSON`
  - Converts to `[DisplayMessage]`:
    - User text messages → `UserTextMessage`
    - User tool_result messages → `ToolResultMessage`
    - Assistant text blocks → `AssistantTextMessage`
    - Assistant tool_use blocks → `ToolCallMessage`
    - Pairs tool_use with matching tool_result → `ToolInteraction`
    - System messages (interesting subtypes) → `SystemDisplayMessage`
    - Compact boundaries → `CompactBoundaryMessage`
    - Skips: file-history-snapshot, progress, queue-operation, last-prompt, etc.
  - Flags `isCompactSummary` on user messages
  - Computes `ConversationStats`
- Unit test: parse the real conversation file and verify counts match expected

**Acceptance:**
- [ ] Parser produces correct display message list
- [ ] Tool calls paired with their results
- [ ] Stats are accurate
- [ ] Compact summaries identified

---

## Task 4: Project Scanner

**Objective:** Implement `ProjectScanner` that discovers all projects and sessions.

**Deliverables:**
- `ProjectScanner.scan() -> [Project]`
  - Scans `~/.claude/projects/`
  - Reads `sessions-index.json` where available
  - Discovers non-indexed JSONL files
  - Extracts first user message from non-indexed files (read first 50 lines)
  - Converts directory slugs to human-readable names
  - Returns sorted project list with sorted sessions
- `SidebarViewModel` wired to `ProjectScanner`

**Acceptance:**
- [ ] All projects discovered
- [ ] Both indexed and non-indexed sessions found
- [ ] Project names are human-readable
- [ ] Sessions sorted by date

---

## Task 5: Sidebar UI

**Objective:** Build the sidebar with project/session listing.

**Deliverables:**
- `SidebarView` with disclosure groups per project
- `ProjectRow`: project name + session count
- `SessionRow`: title/preview + date + message count
- Search field at top filters sessions
- Selecting a session sets it in the view model
- Currently selected session highlighted
- Async loading indicator while scanning

**Acceptance:**
- [ ] Projects expand/collapse
- [ ] Sessions show title and date
- [ ] Search filters work
- [ ] Selection navigates to conversation

---

## Task 6: Conversation View — Basic Rendering

**Objective:** Render conversations in the detail pane as a chat view.

**Deliverables:**
- `ConversationView`: ScrollView with LazyVStack of message views
- `UserMessageView`: blue card with text content
- `AssistantMessageView`: purple card with markdown rendering
- `ToolCallView`: green collapsible card
- `ToolResultView`: green collapsible card
- `SystemMessageView`: orange compact card
- Message headers with role label, timestamp, model tag
- Stats bar at the bottom (pinned, not scrollable)
- Basic markdown rendering (bold, italic, headers, code, lists)
- Compact summary messages with special styling

**Acceptance:**
- [ ] All message types render correctly
- [ ] Tool calls expand/collapse
- [ ] Markdown renders properly
- [ ] Stats bar shows correct counts
- [ ] Smooth scrolling on large conversations

---

## Task 7: Filter Toggles

**Objective:** Implement message type filtering.

**Deliverables:**
- Filter toggle buttons in the toolbar: User, Claude, Tool Calls, System
- All active by default except System
- Toggling a filter immediately hides/shows matching messages
- Filter state persisted in `ConversationViewModel`

**Acceptance:**
- [ ] Each filter toggle works independently
- [ ] Toggling is instant (no re-parse)
- [ ] Filter state remembered per session (or globally)

---

## Task 8: Copy System

**Objective:** Implement single and multi-message copy.

**Deliverables:**
- Copy button on each message header (appears on hover)
- Click copies formatted message to clipboard
- Toast feedback on copy
- Multi-select mode:
  - "Select" toggle in toolbar
  - Selection toolbar with count, Select All, Deselect All, Copy Selected
  - Click messages to toggle selection
  - Gold outline on selected messages
  - Escape exits select mode
  - Cmd+A selects all visible
- Copy format as specified in `05_FEATURES_DETAIL.md`

**Acceptance:**
- [ ] Single message copy works with correct format
- [ ] Multi-select mode activates/deactivates cleanly
- [ ] Selected messages visually highlighted
- [ ] Copy Selected produces correctly formatted output
- [ ] Keyboard shortcuts work

---

## Task 9: Message Editing

**Objective:** Implement in-place message editing.

**Deliverables:**
- Pencil icon on each user/Claude message (appears on hover)
- Click opens inline TextEditor replacing message body
- Done/Cancel buttons
- Dirty state tracking on `Conversation`
- "Unsaved Changes" indicator in toolbar
- Navigate-away warning dialog

**Acceptance:**
- [ ] Can edit user messages
- [ ] Can edit Claude messages (markdown source)
- [ ] Dirty state shown in toolbar and sidebar
- [ ] Cancel reverts changes
- [ ] Warning on navigate-away

---

## Task 10: Save & Backup

**Objective:** Implement save-to-disk with automatic backup.

**Deliverables:**
- `BackupService.backup(filePath:)` — copies to backup directory with timestamp
- `ConversationWriter.write(conversation:, to:)`:
  - For each `RawEntry`: if modified, re-serialize; if not, write `rawJSON` verbatim
  - Omit entries whose index is in `deletedIndices`
  - Atomic write (write to temp file, then rename)
- "Save" button in toolbar (Cmd+S)
- Toast feedback on save
- Backup retention (keep last 20 per session)

**Acceptance:**
- [ ] Backup created before every save
- [ ] Modified messages saved correctly
- [ ] Unmodified entries preserved byte-for-byte
- [ ] Deleted messages removed from file
- [ ] Atomic write prevents corruption

---

## Task 11: JSON Mode

**Objective:** Implement raw JSONL viewing and editing.

**Deliverables:**
- "JSON" toggle button in toolbar (Cmd+J)
- Switches to monospace text editor showing raw JSONL
- Filter: show all vs messages only
- Edits modify the in-memory entries
- On save: validate each line as JSON, highlight errors
- Changes sync between chat mode and JSON mode

**Acceptance:**
- [ ] JSON mode displays raw content
- [ ] Edits persist to in-memory model
- [ ] Invalid JSON lines highlighted on save attempt
- [ ] Switching modes preserves edits

---

## Task 12: Export as Prompt

**Objective:** Implement conversation export for re-use.

**Deliverables:**
- "Export as Prompt" button in toolbar
- Opens sheet with preview of user+Claude text only
- Checkboxes to include/exclude individual messages
- Format options: Labeled, Bare, Markdown
- "Copy to Clipboard" button
- "Save as .txt" button

**Acceptance:**
- [ ] Only user text and Claude text included (no tool calls, system, compact summaries)
- [ ] Toggle individual messages
- [ ] All three formats produce correct output
- [ ] Copy works

---

## Task 13: Right-Click Context Menus

**Objective:** Add context menus to all interactive elements.

**Deliverables:**
- Message context menus per type (as specified in `04_UX_AND_DESIGN.md`)
- Sidebar session row context menus: Open in Finder, Copy Session ID, Copy File Path, Delete Session
- Delete message functionality (strikethrough + muted, undo before save)

**Acceptance:**
- [ ] All context menu items work
- [ ] Delete shows visual feedback
- [ ] Sidebar context menus work
- [ ] "Open in Finder" opens the correct directory

---

## Task 14: Open in Claude Code

**Objective:** Launch Claude Code from the app.

**Deliverables:**
- "Open in Claude Code" toolbar button
- Resolves project path from conversation `cwd`
- Launches terminal with `claude --resume <session-id>`
- Detect available terminal app (Terminal.app, iTerm2, Warp)

**Acceptance:**
- [ ] Claude Code opens in the correct project directory
- [ ] The correct session is resumed
- [ ] Works with at least Terminal.app

---

## Task 15: Settings

**Objective:** Implement the Settings window.

**Deliverables:**
- macOS Settings scene with tabs: General, AI Search, Advanced
- General: display name, theme (System/Dark/Light)
- AI Search: OpenRouter API key (Keychain), model selection, test button
- Advanced: CLI path, backup directory
- Settings persisted via `@AppStorage` / `UserDefaults` + Keychain

**Acceptance:**
- [ ] Settings window opens from app menu
- [ ] Display name changes reflected in message headers
- [ ] Theme toggle works
- [ ] API key stored in Keychain

---

## Task 16: AI Search

**Objective:** Implement AI-powered conversation search.

**Deliverables:**
- Search panel accessible via Cmd+Shift+F
- Text input for natural language query
- Sends conversation summaries to configured OpenRouter model
- Parses response for matching session IDs
- Displays results ranked by relevance
- Click result navigates to conversation
- Loading state while searching
- Error handling for API failures

**Acceptance:**
- [ ] Search finds relevant conversations
- [ ] Results clickable and navigate correctly
- [ ] Error shown if no API key configured
- [ ] Graceful handling of API errors

---

## Task 17: Polish & Performance

**Objective:** Final polish pass.

**Deliverables:**
- Keyboard shortcuts all working
- Animations smooth
- Large conversations (500+ messages) scroll smoothly (LazyVStack verified)
- Empty states for all scenarios
- Edge cases: empty files, malformed JSON, very long messages, missing fields
- FileWatcher: detect when JSONL files change on disk (new messages from active Claude session)
- Memory usage profiling — ensure cached conversations don't leak

**Acceptance:**
- [ ] All keyboard shortcuts documented and working
- [ ] No lag on large conversations
- [ ] App handles malformed data gracefully
- [ ] Live updates when files change
