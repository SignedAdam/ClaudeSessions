# Claude Sessions — Roadmap

A native macOS app for browsing, reading, editing, exporting, and continuing
Claude Code conversations. Built in SwiftUI, no external dependencies.

This is the live roadmap. Older docs in `docs/cycles/CURRENT.md` reflect very early
state and are no longer maintained — work here.

---

## Vision

This app is **not** another Claude client. It's an **archival and continuation
tool** for the JSONL conversations that Claude Code writes to disk. The
defining feature is "clean continuation" — extracting just the human ↔ Claude
dialogue from a heavy working session (full of tool calls, system events,
file snapshots) and forking it into a fresh resumable session that Claude Code
treats as native. Compaction without losing continuity.

Everything else — themes, exports, archive, favorites — exists in service of
that core: making old conversations easy to find, easy to read, easy to reuse.

---

## ✅ Done

### Core data layer
- Reads `~/.claude/projects/*.jsonl` and `sessions-index.json`
- Parser handles all 11 entry types, pairs tool calls with their results
- Lossless round-tripping: every entry keeps its raw JSON; only modified entries are re-serialized on save
- LRU conversation cache (10 entries)
- File size guard (refuses >25MB, hard ceiling at 200MB)
- Background JSONL parse via `Task.detached`, with in-flight cancellation
- FileWatcher (FSEvents) for live reload when files change externally

### Sidebar
- Project tree with disclosure groups
- Sessions sorted newest-first inside each project
- Lazy session row rendering — projects with hundreds of sessions don't all materialize
- Search bar (filters by title, first prompt, project name)
- Session footer: refresh, archive view, hidden toggle, project/session counts
- Selection-by-tap (not List binding — that combination silently breaks with disclosure groups)

### Conversation viewing
- Three modes: **Chat** (filterable, full content), **Reading** (dialogue only, no tools/system), **JSON** (raw)
- Filter pills (human, claude, tools, sys) — only shown in Chat
- Group headers — consecutive messages from the same speaker within 90s share one header
- Tool interaction view: collapsible, tool-specific icons, status dots
- Hover-revealed action buttons in the gutter (edit, copy)
- Markdown renderer (off-main, cached): headers, lists, blockquotes, fenced code with copy buttons, horizontal rules, inline emphasis
- 30k-char cap on giant messages (renders as plain text), 200-line cap on individual code blocks
- Context badge in session header — peak tokens / context window / fill % with traffic-light coloring
- Context detail sheet — visual context map, breakdown by category, cost estimate, cache hit rate
- Dialogue-size pill — `<peak> → <cleaned>` shown next to the clean button

### Editing
- Inline TextEditor on user and assistant messages, same container size as read mode (no layout shift)
- Cancel / Save text actions; `Esc` cancel, `⌘↩` save
- Per-message dirty tracking
- Save **forks** into a new session (never overwrites): original is archived in the sidebar with `· archived` suffix; new file gets a new UUID and sessionId, parent chain rebuilt
- Backup to `~/.claude-sessions-backups/` on every save (defensive third copy)
- Delete messages via context menu — visual strikethrough, undo before save

### Extract / Clean Continuation (the headline feature)
- CleanConversationService strips everything except user + Claude text blocks
- Output: a real JSONL session file with new UUIDs, new sessionId, fresh parent chain
- `usage`, `id`, `stop_details`, `requestId` stripped from cleaned assistant messages so context counts don't lie
- Two extract modes (Settings → Advanced):
  - **newSession** (default) — writes the cleaned JSONL into the project directory and opens with `claude --resume`
  - **pipedPrompt** — extracts plain text and pipes it as the first prompt to a fresh `claude` invocation
- "clean ↗" toolbar button uses your default; right-click for the other mode

### Open in Claude Code
- iTerm2 launch via AppleScript (with Terminal.app fallback)
- Always `cd`s into the project's `cwd` first (Claude Code's `--resume` only sees sessions whose project matches the current dir)
- "resume" button — opens the current session as-is
- Auto-launch after `clean` extraction

### Hide / Archive / Delete
- **Hide** — soft, config-only (`~/.claude-sessions-app/hidden.json`). Per-session and per-project. Toggle visibility via eye icon in sidebar footer.
- **Archive** — physical file move to `~/.claude-sessions-archive/<projectId>/<sessionId>.jsonl` + `.meta.json` with origin metadata. Disappears from Claude Code's view entirely.
- **Archive sheet** — lists all archived sessions, restore button, permanent delete (with confirmation).
- **Move to Trash** — uses macOS Trash via `NSWorkspace.recycle`, recoverable until Trash is emptied.
- **Copy to Project** — duplicates a session into another project, rewriting `cwd` in every entry so `--resume` still works at the destination. Title prefixed with `moved from <orig> ·`.

### Favorites / Pin
- Per-session star (hover icon + context menu)
- Persisted to `~/.claude-sessions-app/favorites.json`
- Dedicated **Favorites** section at the top of the sidebar — cross-project, sorted newest-first
- Project-name hint above each title in the Favorites section so you don't lose track of origin

### Export
- Unified export sheet (icon: `square.and.arrow.up` in the toolbar)
- Four formats:
  - **Markdown** — readable with header, with optional `Include tool calls` toggle (renders inputs as fenced code blocks, outputs as `output` blocks, capped at 10k chars)
  - **JSON** — structured `{session: {id, title, cwd, model, messages: [...]}}`, optional tool calls
  - **Codex CLI** — produces a real `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO>-<sessionId>.jsonl` with `session_meta` + `response_item` + `event_msg` lines
  - **Gemini CLI** — produces a real `~/.gemini/tmp/<projectHash>/chats/session-<ISO>-<id8>.json` with SHA-256 project hash and proper schema
- Three actions: Copy to Clipboard, Save to default CLI directory, Save As…
- Live preview pane (capped at 16k chars)

### Themes
- Five palettes:
  - **Studio** — warm lavender, the everyday default
  - **Paper** — wenge brown + aged gold, late-night reading lamp
  - **Observatory** — dim amber on blue-black, dark-adapted for 2am
  - **Stellar** — vivid navy + gold, NASA-poster vibes
  - **Vellum** — warm parchment with crimson text, gold-leaf interactive elements, navy human-tint, forest-green tool-tint (illuminated manuscript palette, light mode)
- Two conversation styles:
  - **Document** (default) — group headers + open margins
  - **iMessage** — authentic iOS Messages takeover (real iMessage blue, system gray bubbles, palette-independent)
- Ambient color-field background — 4 large soft Lissajous-drifting blobs, near-still motion, theme-aware. Toggleable.
- Theme picker popover anchored to the sidebar footer (top-bar conflict with macOS drag region was unsolvable)

### App chrome
- Custom thin top bar — traffic lights on the left, drag region across the rest; controls live outside the macOS drag-owned area
- Sidebar footer is the central control strip: refresh, archive, hide-toggle, theme picker, settings gear, stats chip
- Bottom bar with labeled metrics: human / claude / tools / duration, plus theme + settings icons mirrored on the right
- Session header: title (click-to-rename with pen icon), close button, cwd path (click-to-copy)
- Hidden title bar with transparent titlebar + `fullSizeContentView`, ambient background extends to the edges

### Settings
- General: display name, theme, show-hidden toggle
- AI Search: OpenRouter API key (Keychain-stored), model picker
- Advanced: CLI path, backup dir, extract mode, continuous backup, archive view shortcut

### Performance / safety
- 200MB hard file ceiling, 25MB soft warning
- All heavy parsing off-main with cancellation
- LazyVStack for sidebar session lists and conversation message lists
- ContextMetrics computation off-main
- @State-cached markdown blocks
- SessionRow is a pure prop-driven view (doesn't subscribe to stores) so a single store update doesn't re-render every row

---

## 🚧 Partially done

### Light mode
- Vellum is a fully light theme, but a few small UI bits still assume dark backgrounds.
- Need an audit pass: spinner colors, divider opacities, hover surfaces in `iMessage` mode.

### Multi-select copy
- `ClipboardService.copyMessages` exists and works.
- No UI yet — no checkboxes, no Cmd+A, no selection toolbar.

### JSON mode
- Read-only viewer with line numbers and type-colored dots.
- No editing — original spec called for in-place JSON editing with validation. Not critical because the main editor handles dialogue edits cleanly.

---

## 🎯 Next up — high value, low cost

### 1. Subagent and history.jsonl browsing
We currently ignore:
- `~/.claude/projects/<project>/subagents/agent-*.jsonl` — real subagent conversations spawned by the Agent tool
- `~/.claude/history.jsonl` — master log of every prompt ever typed (~7000 entries on a heavy user's machine)

**Subagents** would slot under their parent session as nested rows.
**history.jsonl** unlocks "find that one prompt I typed three weeks ago." Build it as a separate tab/sheet rather than inline in the sidebar.

### 2. Save conflict detection
Right now we forge ahead even if the file changed under us. We have FileWatcher already; just need to:
- Compare on-disk modtime to cached modtime at save time
- Show a `keep mine / use disk / merge` dialog if they diverge

### 3. Navigate-away confirmation
If `isDirty` and the user clicks another session, prompt: *"Save your changes to this session before switching?"* — Save / Discard / Cancel.

### 4. Cross-conversation search
Search currently only works within the current conversation, plus the AI search sheet which is per-prompt-only. We want:
- A persistent FTS5 index of all message text across all sessions
- Updated incrementally via FileWatcher
- A unified search UI: type a query, get a ranked list of matching sessions with a snippet of context

### 5. Stats dashboard
A new home-screen module:
- Total tokens consumed (input/output/cache split)
- Cost estimate (with model-aware per-token pricing)
- Most active days, most active projects
- Tool-usage distribution (which tools you call most)
- Weekly graph

We already compute most of this per-session in `ContextMetrics` — extend it to aggregate across all sessions, with caching.

### 6. Selective context injection
Currently `clean` extracts the whole dialogue. Sometimes you want just messages 12-18. Build:
- Multi-select UI (overlaps with #2 above)
- "Extract selected to new session" — same SessionForker pipeline but only the selected messages
- Especially powerful combined with the existing iTerm2 launch

### 7. Quota & usage tracker
Show Anthropic's 5-hour and weekly quota usage. Possible approaches:
- Shell out to `claude` CLI's own usage / status command (need to research what's exposed)
- Parse the `usage` field across recent sessions and approximate
- The first is cleaner but depends on Anthropic exposing it; flagging for research

---

## 🌟 Big ideas — transformative, larger investments

### Real tokenizer
Today we use char-count heuristics for "size of cleaned dialogue." Three options:
- Anthropic's `count_tokens` API (exact, requires API key, slow for bulk)
- Port `cl100k_base` (GPT tokenizer, ~95% accurate for prose, simpler than Claude's actual tokenizer)
- Content-aware heuristics (chars/4 for prose, chars/3 for code, detect via fence) — best free-tier option

Default to heuristics, optionally call `count_tokens` when the user has an API key configured.

### LLM summarization
"Summarize this conversation" using OpenRouter when configured. Two flavors:
- Fast summary at the top of long conversations
- **"Compress this"** — different from `clean`. Replaces bulky tool outputs with one-sentence summaries, then forks into a new resumable session. The conversation feels shorter but Claude still has the gist of what was done.

### Knowledge graph
Sessions implicitly share things: file paths touched, libraries referenced, person names mentioned. A graph view of your sessions linked by these shared elements would be unique to this app — no other tool has this dataset to draw on.

### Plugin / custom export formats
Users define an export format (Jinja-like template) → it appears in the export sheet. Useful for piping conversations into other tools we haven't built native support for.

### iCloud / Dropbox sync of metadata
Favorites, hidden, archive index, and rename-overrides aren't huge files. Sync them across machines so your "Starred" list follows you.

### Conversation version history + diff view
Every save creates a backup. We don't surface them. Build:
- "Revisions" sheet listing all backups with timestamps
- Click two to diff
- Restore-as-new-session

### Live session watching
If Claude Code is currently writing to a JSONL, auto-scroll the conversation view as new entries arrive (we have FSEvents, just need to render the appended portion).

### Session merge
Combine two conversations into one. Useful when context got split across two `--resume`s.

### Compare two sessions side-by-side
A/B view. Useful for "which approach did Claude land on" debugging.

### Custom filesystem locations
Settings option to add additional scan dirs (external drives, restored backups, archives from other machines).

### Drag sessions between projects
Drag from one project folder to another in the sidebar — same as Copy to Project but spatial. Nicer UX.

### Drag messages out of the app
Drop a message onto another app to paste its text. macOS native NSItemProvider hookup.

### Calendar / timeline view
A heatmap of conversation activity. Click a day → see all sessions from that day.

### Custom keyboard shortcuts
A Settings panel that lets users rebind any of our shortcuts.

---

## 🪶 Polish / nits

- Delete the now-unused `ExportPromptView` (superseded by `ExportSheetView`)
- Mark `docs/cycles/CURRENT.md` as superseded by this roadmap, or delete it
- Audit Vellum + iMessage — some hover surfaces still show dark-theme tints
- Animated transitions between Chat/Reading/JSON modes (currently abrupt)
- Better empty state for the archive sheet when nothing is archived
- Project rename — currently inferred from `cwd`; could allow user override
- Right-click context menus still use the system styling (we deferred custom styling because SwiftUI's `.contextMenu` is hard to fully restyle without going to NSMenu)
- Loading toast when scanning very large project trees
- Sidebar footer stat chip wraps at very narrow widths despite `.fixedSize()` — investigate

---

## 🚫 Not doing

- **Full test suite** — not in the current scope.
- **Becoming a Claude client** — no chat input, no message sending. This is purely an archive / continuation tool.
- **Custom-styled context menus** — would require building a custom popover replacement for `.contextMenu`. Deep rabbit hole, low aesthetic ROI.
- **Theme/Settings buttons in the title bar** — deferred because macOS drag regions own that space. They live in the sidebar footer / bottom bar instead.
- **Streaming JSONL parser** — current full-file parse is fine up to 25MB. The file size ceiling is the right answer for the long tail.

---

## File map

```
ClaudeSessions/Sources/ClaudeSessions/
├── ClaudeSessionsApp.swift     — @main, environment objects, commands, window config
├── AppState.swift              — central ObservableObject; selection, edits, extract, save, archive
├── ContentView.swift           — split view + ambient background + top/bottom bars
├── Models/                     — Codable JSONL types, AnyCodable, display models, session index
├── Services/
│   ├── ProjectScanner.swift    — discovers ~/.claude/projects/
│   ├── ConversationParser.swift — JSONL → Conversation
│   ├── ConversationWriter.swift — lossless serialization
│   ├── BackupService.swift     — defensive backups
│   ├── BackupEngine.swift      — continuous backup mode
│   ├── ClipboardService.swift  — formatted multi-message copy
│   ├── CleanConversationService.swift — dialogue extraction (the headline)
│   ├── SessionCreator.swift    — write new JSONL + register in index
│   ├── SessionForker.swift     — non-destructive save (archives original)
│   ├── ArchiveService.swift    — file-level archive/restore
│   ├── HiddenStore.swift       — soft visibility
│   ├── FavoritesStore.swift    — starred sessions
│   ├── ExportService.swift     — Markdown / JSON / Codex / Gemini
│   ├── ThemeStore.swift        — palettes + conversation style
│   ├── ContextMetrics.swift    — token usage, cost, breakdowns
│   ├── AISearchService.swift   — OpenRouter
│   └── …
├── Utilities/
│   ├── DateFormatting.swift, FileWatcher.swift, KeychainService.swift,
│   ├── ProcessLauncher.swift   — iTerm2 / Terminal launch
│   └── Theme.swift             — palette definitions + isLight detection
└── Views/
    ├── Conversation/           — message views, header, container, group header, export sheet
    ├── Sidebar/                — sidebar, sessionrow, favorites section, footer
    ├── JSONMode/, Search/, Settings/, Shared/, Toolbar/
    ├── ArchiveView.swift, BottomBarView.swift, ContextDetailView.swift,
    ├── HomeDashboardView.swift, MoveSessionView.swift, ThemePickerView.swift,
    ├── TopBarView.swift, WavyBackground.swift
```
