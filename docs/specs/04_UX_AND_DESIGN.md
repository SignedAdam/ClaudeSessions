# UX & Design Specification

## Design Philosophy

- **Native macOS.** Use system materials, vibrancy, SF Symbols, native controls. No web-app aesthetic.
- **Dark by default.** Dark mode is the primary design target. Light mode must also work but dark is the priority. The color palette matches Claude Code's terminal aesthetic — deep backgrounds, colored accents per message role.
- **Dense but readable.** Conversations can be long. Compact enough to see many messages without excessive whitespace, but not cramped. Similar density to iMessage or Slack.
- **Zero-learning-curve.** Anyone who has used a chat app can use this immediately.

## Color System

### Dark Mode (Primary)

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#0d1117` | Window/app background |
| `surface` | `#161b22` | Sidebar, toolbars, stats bar |
| `surface2` | `#1c2128` | Cards, elevated surfaces |
| `border` | `#30363d` | Dividers, borders |
| `text` | `#e6edf3` | Primary text |
| `textMuted` | `#8b949e` | Secondary text, timestamps |
| `userAccent` | `#58a6ff` | User message chrome (blue) |
| `userBg` | `#0c2d6b` | User message background |
| `userBorder` | `#1f4a8a` | User message border |
| `claudeAccent` | `#d2a8ff` | Claude message chrome (purple) |
| `claudeBg` | `#1a0f2e` | Claude message background |
| `claudeBorder` | `#3b2266` | Claude message border |
| `toolAccent` | `#7ee787` | Tool call/result chrome (green) |
| `toolBg` | `#0d2818` | Tool call/result background |
| `toolBorder` | `#1a4028` | Tool call/result border |
| `systemAccent` | `#f0883e` | System message chrome (orange) |
| `systemBg` | `#2a1a05` | System message background |
| `systemBorder` | `#4a2f0f` | System message border |
| `selectionAccent` | `#f0c000` | Selection highlight (gold) |
| `danger` | `#f85149` | Destructive actions, errors |

### Light Mode

Inverted luminance values with the same hue families. User = blue, Claude = purple, Tool = green, System = orange. Backgrounds become light pastels of the same hues.

## Typography

- **Body text:** System font (SF Pro), 14pt, regular weight
- **Message headers:** System font, 11pt, semibold, uppercase, 0.5pt tracking
- **Code:** SF Mono, 13pt
- **Timestamps:** System font, 11pt, regular, muted color
- **Sidebar titles:** System font, 13pt, semibold
- **Sidebar subtitles:** System font, 12pt, regular, muted

## Layout

### Window

- Minimum size: 800 x 500
- Default size: 1100 x 700
- Resizable with proper responsive behavior
- Title bar: standard macOS with toolbar
- Sidebar: `NavigationSplitView` with collapsible sidebar (250px default, min 200, max 350)

### Sidebar (Left Panel)

The sidebar has two sections, displayed as a single scrollable list with section headers:

**1. Projects section**
Each project is a disclosure group that expands to show its sessions:

```
▼ dev                           (12 sessions)
    Nootropic Stack Research     Apr 1
    Conversation Viewer          Apr 5
    MKULTRA-II Project           Apr 5
▶ shortimize-backend            (98 sessions)
▶ shortimize-app                (19 sessions)
▼ Narkis                        (20 sessions)
    Session title or preview...  Mar 24
    ...
```

- Project names are derived from `originalPath` in `sessions-index.json`, or from the directory slug (convert `-Users-alice-dev-shortimize-backend` → `shortimize-backend`)
- Session rows show: title/summary (from index) or first ~60 chars of first user message, and date
- Sessions sorted by date (most recent first)
- Currently selected session is highlighted
- Search field at the top of the sidebar filters sessions by text match on title/first-prompt

**2. Session row detail**
- Title: summary from index, or truncated first prompt, or "Untitled"
- Subtitle: date + message count
- Right-aligned: modified date
- If session has unsaved edits: small orange dot indicator

### Conversation View (Right Panel)

The main content area. A scrollable list of message bubbles.

**Toolbar** (at top of conversation view):
- Filter toggles: `User` `Claude` `Tool Calls` `System` — each is a pill button, active by default except System
- Mode toggles: `Chat` | `JSON` — switches between rendered chat view and raw JSONL editor
- Actions: `Select` toggle, `Export as Prompt`, `Open in Claude Code`

**Message list:**
- Each message is a rounded-corner card with:
  - Header bar: role label, model tag (for Claude), timestamp, copy button (right-aligned)
  - Body: rendered content
  - Edit button: small pencil icon below the message body, appears on hover
- Messages are separated by 12px vertical gap
- Compact summary messages (isCompactSummary) are rendered with a special "Context summary" style — muted, collapsible, with a label saying "Conversation was compacted here"

**Tool calls and results:**
- Rendered as collapsible cards
- Header shows: tool name, description/summary of input
- Click to expand/collapse the full input/output
- Collapsed by default
- Tool call + its result visually grouped (slightly indented or connected)

**Stats bar** (bottom of conversation view, always visible):
- User count, Claude count, Tool call count, System count, Duration
- Fixed height, never scrolls, never overlaps conversation content

### Edit Mode

When the user clicks the edit (pencil) button on a message:
1. The message body becomes an editable `TextEditor`
2. A "Save" and "Cancel" button appear below the editor
3. The message gets a subtle yellow/gold border to indicate it's being edited
4. Other messages remain read-only
5. Only one message can be edited at a time
6. Editing changes the in-memory model. Nothing saves to disk yet.
7. The toolbar shows a "Unsaved changes" indicator and a "Save to Disk" button

For Claude messages, the user edits the markdown text. For user messages, the user edits the plain text.

### JSON Mode

When the user switches to JSON mode:
1. The conversation view is replaced by a monospace text editor showing raw JSONL
2. Each line is a JSON object, syntax highlighted
3. The user can edit any line
4. Same save behavior: changes are in-memory until explicit save
5. Validation: on save, each line is validated as valid JSON. Invalid lines are highlighted in red with an error message.
6. A toggle to show/hide non-message entries (file-history-snapshot, progress, etc.)

### Multi-Select Mode

When the user clicks "Select" in the toolbar:
1. A selection toolbar appears below the main toolbar: `[0 selected] | Select All | Deselect All | Copy Selected`
2. Each visible message gets a checkbox on the left side
3. Clicking a message toggles its selection
4. Selected messages get a gold outline
5. "Copy Selected" copies all selected messages in chronological order, formatted as:

```
[Adam — 5:02 PM]
message text

[Claude — 5:03 PM]
response text with markdown

[Tool: Bash — 5:03 PM]
ls -la /Users/alice/dev

[Result — 5:03 PM]
total 128...
```

6. `Escape` exits select mode
7. `Cmd+A` selects all visible messages (respecting current filters)

### Export as Prompt

The "Export as Prompt" action:
1. Opens a sheet/panel showing a preview of the extracted conversation
2. Only includes `user` text messages and `assistant` text blocks (no tool calls, no system messages, no compact summaries)
3. Formats as a clean prompt:

```
[User]
first message text

[Claude]
first response text

[User]
second message text

[Claude]
second response text
```

4. The user can toggle individual messages on/off in the preview
5. "Copy to Clipboard" button at the bottom
6. "Open as New Claude Code Session" button — this writes the conversation to a temp file and runs `claude --continue <file>` or similar

### Right-Click Context Menus

Right-clicking a message shows:

**On a user message:**
- Copy Message
- Copy as Prompt (just this message, formatted)
- Edit Message
- Select from Here to End
- Delete Message (marks for deletion, shown with strikethrough, committed on save)

**On a Claude message:**
- Copy Message
- Copy as Prompt (just this response, formatted)
- Edit Message
- Copy Raw Markdown
- Select from Here to End
- Delete Message

**On a tool call:**
- Copy Tool Input
- Copy Tool Input as JSON
- Expand / Collapse
- Delete (marks tool call + its result for deletion)

**On a tool result:**
- Copy Result
- Expand / Collapse
- Delete

### Settings

A standard macOS Settings window (`Settings` scene) with tabs:

**General:**
- Display name (shown as "Adam" or custom name in message headers, replacing "You")
- Theme: System / Dark / Light

**AI Search:**
- OpenRouter API Key (secure text field, stored in Keychain)
- Model selection (dropdown: default to `anthropic/claude-sonnet-4`, list common models)
- Test connection button

**Advanced:**
- Claude Code CLI path (auto-detected, override available)
- Backup directory location (default: `~/.claude-sessions-backups/`)
- Show/hide: compact summaries, progress entries, queue operations

## Interactions & Polish

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+F` | Focus search in sidebar |
| `Cmd+Shift+F` | AI search (opens search panel) |
| `Cmd+C` | Copy selected message(s) when in select mode |
| `Cmd+A` | Select all visible when in select mode |
| `Cmd+S` | Save changes to disk (when dirty) |
| `Cmd+E` | Toggle edit on focused message |
| `Cmd+J` | Toggle JSON mode |
| `Escape` | Exit select mode / cancel edit / close panel |
| `↑ / ↓` | Navigate sessions in sidebar |
| `Cmd+1` | Show/hide sidebar |

### Animations

- Sidebar expand/collapse: standard SwiftUI `withAnimation(.easeInOut(duration: 0.2))`
- Message fade-in on load: staggered opacity animation
- Tool call expand/collapse: height transition with `clipShape`
- Toast feedback: slide up, pause, fade out (2 seconds)
- Selection glow: subtle pulse on the gold border when first selected

### Empty States

- No conversations found: "No Claude Code conversations found. Claude Code stores conversations in ~/.claude/projects/. Start a conversation with Claude Code to see it here."
- No messages match filter: "No messages match the current filters."
- AI search with no key: "Set your OpenRouter API key in Settings to use AI search."
