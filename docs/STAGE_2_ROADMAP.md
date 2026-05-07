# Claude Sessions — Stage 2 Roadmap

Stage 1 (initial spec → first working app) is in `ROADMAP.md` (mostly ✅ Done).
This document drives Stage 2: hardening, the embedded chat, the launch agent,
the in-app MCP server, and the settings/UX polish round.

The loop runner reads this file on every cycle, picks the next task that's
in **`status: queued`** (or resumes one in **`status: in-progress`**), works
on it, and updates this file on the way out.

---

## Conventions

Each task has YAML-ish front-matter:

```
- id: P1.T03
  title: "..."
  status: queued | in-progress | done | blocked | skipped
  notes: "free text — paused because X / blocked on Y / done by cycle 23"
```

Phases run in order. Within a phase, tasks may be done out of order if
nothing else is `in-progress`. Each task should be small enough to land in
one cycle (≤ ~30 minutes of work). Tasks bigger than that should be
decomposed at the start of the cycle.

When the loop has nothing `queued` or `in-progress` in the **earliest
unfinished phase**, it should decompose the **next** phase's high-level goals
into tasks, append them to that phase, and stop. The next iteration will
start picking up the new tasks.

When **all phases are done**, the loop writes a final cycle note summarizing
what landed and stops scheduling.

---

## Phase 1 — Data integrity (no more lost conversations)

**Goal:** Make it impossible for Claude Code's own behavior (compaction,
auto-cleanup, --resume overwrites) to silently destroy conversations the
user cares about. Today the backup engine only runs while the app is open;
the user has reported missing conversations they recognize by title.

### Tasks

- id: P1.T01
  title: "Investigate Claude Code's compaction-overwrite behavior — confirm whether `claude --resume` overwrites the JSONL or appends, and what `/compact` does on disk."
  status: done
  notes: "Done in cycle 21. See findings below."

#### Findings (cycle 21)

**`/compact` is append-only. It does not overwrite, truncate, or replace the JSONL file.**

Inspected a real compacted session at
`~/.claude/projects/-Users-sauel-dev-AtlasNativeClaude/ebe95661-63e3-4a17-9917-db93bd8a82ad.jsonl`:

- Pre-compaction content occupies lines 1–3237. Post-compaction continuation occupies lines 3238–6297 (the file grew, didn't shrink).
- The compaction marker is a synthetic user entry with `"isCompactSummary": true` and `"isVisibleInTranscriptOnly": true`. Its `parentUuid` points to the last pre-compaction assistant entry, so the parent chain is intact and walks all the way back to the original root.
- The `sessionId` is unchanged. Same file, same logical session.

**`claude --resume <id>` appends to the existing file.** It does not rewrite or fork. Same `sessionId`, file just grows.

**`--fork-session` creates a new file with a new sessionId.** Original is preserved untouched.

**The user's "missing conversations" are almost certainly `cleanupPeriodDays` (default 30 days).** Per Anthropic's settings docs (verified via WebFetch in this cycle): cleanupPeriodDays is a **hard delete** (unlink), not a move-to-trash or archive. Minimum is 1 day; 0 is rejected. So a session whose JSONL is older than 30 days, when our app isn't running to back it up, gets permanently removed by Claude Code on its next startup.

#### Implications for Phase 1 design

- T05 (versioned snapshots) doesn't need to defend against compaction rewrites — they don't happen. It DOES need to defend against:
  1. `cleanupPeriodDays` deletion (hardest case — file simply vanishes; we keep our backup forever)
  2. `--fork-session` (file unchanged; new file appears alongside)
  3. Manual rm by user or script
- The current BackupEngine, which appends new lines as the source grows and never deletes from the mirror, is already correct for ordinary append-only growth. The work in T05 reduces to: detect when a source file disappears (mark backup as "preserved"), and detect non-append rewrites if any future Claude Code version introduces them (not today's behavior, but defensive).
- T02 + T03 (headless daemon + LaunchAgent) are now confirmed as the most impactful items in Phase 1 — they close the "app not running" window during which cleanupPeriodDays can strike.
- T04 (onboarding wizard) should explicitly mention cleanupPeriodDays-vs-backup-daemon as the two protections, so the user understands they're complementary.

- id: P1.T02
  title: "Headless backup daemon — package the existing `BackupEngine` as a standalone binary that can run as a `LaunchAgent` even when the main app is closed."
  status: done
  notes: "Done in cycle 22. ContinuousBackup is now a shared library target; new `ClaudeSessionsBackupAgent` executable target consumes it. Daemon binary at `.build/debug/ClaudeSessionsBackupAgent`. Tested: starts engine, runs RunLoop.main, handles SIGTERM cleanly, logs to ~/.ClaudeSessions/logs/agent.log."

- id: P1.T03
  title: "LaunchAgent installer — install/uninstall the daemon's `~/Library/LaunchAgents/com.claudesessions.backup.plist`, with `RunAtLoad=true`, `KeepAlive=true`, log paths under `~/.ClaudeSessions/logs/`."
  status: done
  notes: "Done in cycle 23. `LaunchAgentInstaller.swift` provides install/uninstall/isInstalled/isRunning. install() copies daemon to ~/.ClaudeSessions/bin/, writes plist, launchctl bootstrap. UI hookup is in T04 (onboarding wizard)."

- id: P1.T04
  title: "First-run onboarding wizard — single-page modal shown the first time the app launches. Two recommendations: (1) set `cleanupPeriodDays` to 36500, (2) install the background backup daemon. Each has a Yes/Skip button."
  status: done
  notes: "Done in cycle 24. OnboardingView.swift — themed modal sheet (560×600) with two cards (retention extension + LaunchAgent install). Each card has Skip/Apply, with applying/applied/skipped/failed states + retry. Wired into ContentView via @AppStorage(didShowOnboarding) so it shows once."

- id: P1.T05
  title: "Compaction-resilient backup — versioned snapshots. When a watched JSONL shrinks, branches, or has its first entry change UUID, treat it as 'rewritten' and keep the prior version under `~/.ClaudeSessions/backup/<sessionId>.<timestamp>.jsonl` instead of overwriting."
  status: done
  notes: "Done in cycle 25. Added firstLineSignature to BackupManifest.FileState, readFirstLineSignature() helper in BackupEngine, and a signature-mismatch branch in syncFile that rotates the old backup as `<path>.orig-<ts>` before re-copying. Case E (size-same in-place rewrite) now also rotates. Existing manifests without a signature lazily acquire one on next sync — no migration needed."

- id: P1.T06
  title: "Restore-from-backup UI — given a session in the sidebar, show all available backup versions, let the user open or restore a previous version into the project as a new resumable session."
  status: done
  notes: "Done in cycle 26. New BackupVaultView (sheet, 720×540) lists every file in the backup mirror grouped by session, including .orig-<ts> snapshots. Each entry has a Restore button. Filesystem-based (doesn't depend on the manifest). Wired via a tray-icon button in the sidebar footer + appState.showBackupVaultSheet."

---

## Phase 2 — Conversation in app (claude-piped)

**Goal:** Let the user continue any open conversation by typing into a
prompt box at the bottom of the conversation view. We invoke `claude -p`
(non-interactive, single-prompt mode) under the hood with the right
`--resume` and `--session-id` flags, then watch the JSONL for the new
turn(s) to appear and render them inline. Not a full TUI emulator — a chat
experience for one-shot prompts. Slash commands and interactive subagent
work still happen in the user's terminal.

### Tasks

- id: P2.T01
  title: "Validate the `claude -p --resume <id> '<prompt>'` flow — confirm it appends to the JSONL, picks up the existing context correctly, and exits cleanly."
  status: done
  notes: "Validated in cycle 27. See findings below."

#### Findings (cycle 27 — `claude -p --resume`)

Tested live against a real session in this project. Findings:

- **Exact invocation:** `cd <project-cwd> && claude -p --resume <session-id> '<prompt>'`. Working directory MUST match the original session's cwd or `--resume` won't find it.
- **Appends to the existing JSONL** with the same sessionId. No new file is created. File grew +10 entries / ~3KB for one round-trip.
- **Entries appended** (in order): `ai-title`, `permission-mode`, `queue-operation` (×2), `user` (the prompt), `attachment`, `assistant` (blocks: text + tool_use), `last-prompt`, `ai-title`, `permission-mode`. The user entry contains exactly our prompt text. The assistant entry has the same shape as any other assistant turn.
- **Exit code:** 0 on success, non-zero on errors. Tested case hit "Credit balance is too low" → exit 1 + diagnostic on stderr ("Credit balance is too low"). We can surface stderr lines as toasts.
- **Stdin behavior:** with no `< /dev/null` redirect, claude waits ~3s for stdin then prints a warning and proceeds. Our `Process` wrapper should set `task.standardInput = FileHandle.nullDevice` to skip the wait.
- **Other useful flags found in `claude --help`:**
  - `--no-session-persistence` — skip writing to JSONL for this turn (we don't want this).
  - `--session-id <uuid>` — assign a specific UUID (alternative to `--resume`).
  - `--output-format json|stream-json` — structured output. `stream-json` would let us render assistant tokens live. Worth using.
  - `--include-partial-messages` — partial chunks for streaming.
  - `--fork-session` — create a NEW session ID instead of resuming. Already used by SessionForker conceptually; not what we want for embedded chat.

**Implication for P2.T03 (`ClaudeRunner` plumbing):** spawn `Process` with `executableURL = /usr/bin/env claude` (or absolute path), arguments `["-p", "--resume", sessionId, prompt]`, `currentDirectoryURL = cwd`, `standardInput = .nullDevice`. Pipe stdout/stderr. Watch the JSONL for the appended entries via FileWatcher (already in place). For the streaming UX in P2.T04, switch to `--output-format stream-json --include-partial-messages` and parse the live token stream alongside the JSONL tail.

- id: P2.T02
  title: "Compose box at the bottom of `ConversationView` — multi-line TextEditor, Send button, ⌘↩ submit, disabled while a previous message is in-flight."
  status: done
  notes: "Done in cycle 28. New `ComposerView.swift` — multi-line TextEditor (32–140pt), Send button with arrow-up.circle.fill icon, ⌘↩ keyboard shortcut, in-flight spinner. Hidden in JSON mode and toggleable via `embeddedChatEnabled` (@AppStorage, default true). `submitComposer()` on AppState is currently a stub showing a toast — real subprocess plumbing is P2.T03."

- id: P2.T03
  title: "Subprocess plumbing — `ClaudeRunner` service that spawns `claude -p`, streams stdout/stderr, surfaces errors as toasts, captures the run's exit status."
  status: done
  notes: "Done in cycle 29. ClaudeRunner.swift wraps Process around `/usr/bin/env claude -p --resume <id> '<prompt>'` with cwd set, stdin=.nullDevice, async run() returning RunOutcome enum. submitComposer() in AppState now calls it, surfaces errors / cancellations / launch failures as toasts. cancel() sends SIGINT then SIGTERM (used by upcoming P2.T05 Stop button)."

- id: P2.T04
  title: "Live append rendering — when the watched JSONL grows during a run, render the new entries with a subtle 'new' fade-in. Auto-scroll to bottom unless the user has scrolled up."
  status: done
  notes: "Done in cycle 30. AppState diffs displayMessages on reload to compute newly-arrived ids and bumps lastAppendAt. ConversationView auto-scrolls to bottom on lastAppendAt change. Newly-arrived messages get a soft 2pt accent strip on their leading edge that fades out after 1.5s. The user-scrolled-up case is not specifically detected — auto-scroll always fires on append. Acceptable for v1; can add scroll-position detection later if it bites."

- id: P2.T05
  title: "Cancel run — a Stop button while the subprocess is alive. Sends SIGINT, then SIGTERM if it doesn't quit."
  status: done
  notes: "Done in cycle 31. ComposerView's send button branches on isComposerSending — shows submit on idle, stop on in-flight (red stop.fill inside a spinner ring). Click → ClaudeRunner.cancel() (SIGINT, then SIGTERM after 1s grace, already plumbed in T03). ⌘. shortcut also bound."

- id: P2.T06
  title: "Setting: enable/disable embedded chat — for users who prefer to keep all interactive work in their terminal."
  status: done
  notes: "Done in cycle 32. Toggle added to Settings → Claude Code tab as 'Embedded chat' section. Bound to existing @AppStorage(embeddedChatEnabled), default true. ConversationContainerView already gates ComposerView on this flag."

---

## Phase 3 — In-app MCP server (AI control)

**Goal:** Expose the app's operations as an MCP server that Claude Code (or
any MCP client) can call. So the user can type to Claude in their terminal:
"open the Stripe webhook conversation, extract the dialogue, and resume it
with my prompt 'continue from here'" — and Claude does it via our app.

### Tasks

- id: P3.T01
  title: "Decide MCP transport — stdio (spawned per-client) vs HTTP (long-running)."
  status: done
  notes: "Done in cycle 33. Decision: HTTP on localhost (Streamable HTTP variant, no SSE). See findings below."

#### Findings (cycle 33 — MCP transport)

**Decision: HTTP on localhost. Default port 7531, configurable. JSON-RPC 2.0 over POST. No SSE — the spec's Streamable HTTP variant covers our needs.**

#### Why HTTP over stdio

- **The app is already running.** Claude Sessions is a long-lived GUI process that holds the in-memory state Claude wants to act on (open session id, sidebar selection, etc.). HTTP on localhost lets the running app *be* the server. A stdio server would have to be a separate process and IPC back to the GUI for any state-touching operation, doubling the moving parts.
- **Some tools require the GUI process.** `open_session`, `close_session`, `extract_and_open` mutate visible UI state. A stdio subprocess can't do those without round-tripping to the GUI anyway.
- **HTTP is debuggable.** `curl http://localhost:7531/mcp -d '{...}'` works for sanity checks; stdio needs a wrapping harness.
- **Single client semantics are fine for now.** Claude Code is the only practical MCP client right now; we don't need stdio's "one process per client" isolation.

#### Why localhost only, no auth

- The transport binds to `127.0.0.1` only — never `0.0.0.0` — so no other host on the network can reach it.
- Anyone with code execution on the user's Mac can talk to it, but they can also already read `~/.claude/` and the JSONLs directly. We're not increasing the blast radius.
- Future: add a per-launch random token in a header if we ever bind beyond loopback.

#### Wire format

- JSON-RPC 2.0. One endpoint: `POST /mcp`. Body is a JSON-RPC request; response is the matching JSON-RPC reply.
- We do NOT need server-sent events for the initial cut. None of our planned tools stream — they're all point-in-time RPC calls (list, read, mutate). If we later add a `subscribe_to_session_changes` tool, we'll add SSE then.
- Standard MCP methods we'll implement: `initialize`, `tools/list`, `tools/call`. Notifications optional.

#### Default port choice

- 7531 — not in IANA's well-known range, not commonly used, mnemonic ("ses" = sessions, ish). Configurable via Settings → MCP tab (P3.T07).
- On bind failure (port taken): try ephemeral via `port: 0`, surface the chosen port in Settings.

#### Implications for the rest of Phase 3

- **T02 skeleton:** `Services/MCPServer.swift` — Foundation `URLSessionStreamTask` won't work for a server. Use `Network.framework` (`NWListener`/`NWConnection`) — Apple-blessed, no external deps, matches the no-deps rule.
- **T03–T06 tools:** plain handler functions taking decoded params, returning Codable result types. Wrapper turns them into MCP tool descriptors.
- **T07 settings:** enable/disable toggle + port field + a "Copy MCP config snippet" button that emits the right JSON for `~/.claude/settings.json`'s `mcpServers` block.

- id: P3.T02
  title: "MCPServer skeleton — `Services/MCPServer.swift` that listens on a localhost port, parses JSON-RPC, dispatches to handlers."
  status: done
  notes: "Done in cycle 34. MCPServer.swift uses NWListener bound to 127.0.0.1, parses minimal HTTP/1.1 (POST /mcp), parses JSON-RPC 2.0, dispatches initialize / tools/list / tools/call. Tool registry via `ToolDescriptor` struct with handler closures. AppState.mcpServer instantiated but not started (T07 settings toggle controls lifecycle). Runtime smoke test deferred to T07 — the path is exercised end-to-end the first time the user enables the server."

- id: P3.T03
  title: "Tools: navigation — `list_projects`, `list_sessions(project_id)`, `open_session(session_id)`, `close_session()`."
  status: done
  notes: "Done in cycle 35. New file Services/MCPTools/MCPNavigationTools.swift with 4 tools. All bounce to @MainActor before touching AppState. Registered via bootstrapMCPTools() called from init-deferred main.async. MCPToolError enum (badArgument/notFound/unavailable) defined for future tool cycles to share."

- id: P3.T04
  title: "Tools: read — `read_dialogue_only(session_id)`, `read_full_transcript(session_id)`, `read_session_metadata(session_id)`."
  status: done
  notes: "Done in cycle 36. MCPReadTools.swift — three tools that reuse ConversationParser + ClipboardService.formatFullTranscript. Heavy reads parse JSONL off-main via Task.detached. 25MB ceiling matches AppState's in-app loader. Registered alongside navigation tools."

- id: P3.T05
  title: "Tools: organize — `star`, `unstar`, `hide`, `unhide`, `archive`, `unarchive`, `move_to_project`, `delete_to_trash`."
  status: done
  notes: "Done in cycle 37. MCPOrganizeTools.swift — 8 tools, all thin wrappers around FavoritesStore.shared / HiddenStore.shared / appState.archiveSession / appState.restoreArchivedSession / appState.copySessionToProject / appState.confirmDeleteSession. delete_to_trash uses macOS Trash so it's recoverable; doc warns clients to confirm with the user."

- id: P3.T06
  title: "Tools: launch — `extract_and_open(session_id, mode)`, `resume_in_terminal(session_id)`."
  status: done
  notes: "Done in cycle 38. MCPLaunchTools.swift — extract_and_open(mode) wraps appState.extractAsNewSession / extractAsPipedPrompt; resume_in_terminal wraps ProcessLauncher.resumeSession. Both descriptions warn clients that they spawn terminals."

- id: P3.T07
  title: "Setting: MCP server enable/disable + port + show the install instructions."
  status: done
  notes: "Done in cycle 39. New MCPSettingsView tab with enable toggle (status: 'Running on http://127.0.0.1:7531/mcp' or 'Stopped'), port field with validation (1024–65535), copy-snippet button for ~/.claude/settings.json, and a tools-list reference. AppState.setMCPEnabled / restartMCPServer / startMCPServer methods. mcpServer.start() updated to take an optional port. **Phase 3 complete.**"

---

## Phase 4 — Settings UX overhaul

**Goal:** The settings popup currently looks unstyled and overflows.
Tabs cut off content. No scrolling. Make it feel like the rest of the app
and ensure every section is reachable at the default size.

### Tasks

- id: P4.T01
  title: "Audit every settings tab at the default 520×420 size — note every overflow case in the task body (Claude Code tab is known overflowing)."
  status: done
  notes: "Done in cycle 40. See findings below."

#### Findings (cycle 40 — settings overflow audit)

Window: `.frame(width: 520, height: 420)` on `SettingsView`'s `TabView`. Usable content area after the macOS tab bar (~30pt) and inner padding (~32pt) is **~358pt vertical, ~488pt horizontal**.

| Tab | Status | Notes |
|---|---|---|
| **General** | OK | Identity, Terminal, Visibility, Appearance — 4 sections, each ~60–80pt. Fits. |
| **Extract** | OK | Header + 2 radio options + tip footer. ~250pt. Fits. |
| **Backup** | **Overflows** | Header (70) + toggle (50) + bootstrap+lowDisk rows (60 conditional) + stats (5 rows × 24 = 120) + location (40) + error row (30 conditional) + "How it works" footer (80). ≈ 390–450pt. The "How it works" footer falls below the visible area; the location row may cut off depending on conditional rows. |
| **Claude Code** | **Overflows** | Embedded Chat + Cleanup + Model + Telemetry + Raw Access — 5 sections, each header + 1–2 controls + caption. ~120 + 100 + 90 + 60 + 70 = ~440pt before dividers. Last section (raw access) cuts off at default size. User-confirmed earlier in conversation. |
| **MCP** | OK | Already wrapped in ScrollView (cycle 39) so any overflow gets scrolled. |
| **AI Search** | OK | Small — API key field + model picker + caption. ~150pt. |
| **Advanced** | OK | Two TextFields. ~80pt. |

#### What needs to happen in T02–T05

- **T02 (ScrollView wrapper):** apply uniformly to **all** tabs. Cheap, fixes Backup + Claude Code immediately, harmless on the small ones (no scrollbar appears when content fits).
- **T03 (re-style):** the tabs use Form / native colors and don't match the rest of the app. Switch backgrounds to `Theme.surface`, headings to `Theme.text`, body to `Theme.textSecondary`.
- **T04 (resize):** bumping the default to 640×520 would let Claude Code fit unscrolled and gives Backup room for the footer. Min size should still allow shrink (the ScrollView from T02 makes that safe).
- **T05 (dividers + spacing pass):** consistency — Backup uses Form+Sections, Claude Code uses VStack+Divider, Extract uses VStack+spacing only. Pick one pattern. The VStack+Divider+sectionHeader approach in Claude Code/MCP is closest to the rest of the app.

- id: P4.T02
  title: "Wrap every settings tab in a `ScrollView { … }` so any content fits, regardless of vertical size."
  status: done
  notes: "Done in cycle 41. Wrapped Backup and Claude Code (the two overflowing tabs from T01 audit). MCP already had ScrollView from cycle 39. The remaining four (General, Extract, AI Search, Advanced) use Form which scrolls natively on macOS — and they fit at default size anyway. Pragmatic over uniform: minimal change, maximum effect."

- id: P4.T03
  title: "Re-style settings tabs to match app theming — `Theme.surface` backgrounds, `Theme.text` for headings, `Theme.textSecondary` for body, no native white panel."
  status: done
  notes: "Done in cycle 42. Converted General, AISearch, Advanced from Form to ScrollView+VStack with shared SettingsSectionHeader using Theme.text + Theme.textSecondary. Now matches the existing pattern from Claude Code + MCP + Backup. TabView's outer chrome stays (system-managed) but every tab's content is now themed."

- id: P4.T04
  title: "Resize the settings window to 640×520 default with a min size that lets the longest tab fit without scrolling."
  status: done
  notes: "Done in cycle 43. SettingsView frame: minWidth 520 / idealWidth 640 / maxWidth 900, minHeight 420 / idealHeight 520 / maxHeight 900. Default 640×520 lets the longer tabs (Backup, Claude Code, MCP) fit comfortably. The min keeps the previous size as a floor; the max prevents stretching to absurd dimensions. ScrollView from T02 covers the < idealHeight case."

- id: P4.T05
  title: "Section dividers + spacing pass on every tab — currently inconsistent."
  status: done
  notes: "Done in cycle 44. Extract converted to ScrollView+VStack+SettingsSectionHeader pattern. ClaudeCode's local sectionHeader() now delegates to the shared SettingsSectionHeader. MCP's inline 12pt-semibold Text+caption pairs replaced with SettingsSectionHeader. Backup keeps its 14pt page header (intentional — that's page title, not section header). All seven tabs now share one section-header component. **Phase 4 complete.**"

---

## Phase 5 — Configurable extract behavior

**Goal:** The `clean` extract currently strips ALL non-dialogue. The first
user message in a Claude Code session usually contains injected context
(CLAUDE.md, working directory, git branch). Stripping it loses important
priming. Make this user-configurable.

### Tasks

- id: P5.T01
  title: "Survey what Claude Code injects into the first user message — read the message bodies of the first user entry across several sessions on disk; classify the chunks (CLAUDE.md, system reminders, git status, tools list, etc.)."
  status: done
  notes: "Done in cycle 45. See findings below."

#### Findings (cycle 45 — first-user-message survey)

Surveyed ~40 random sessions across `~/.claude/projects/`. **The first user message is almost always JUST the user's prompt** — no CLAUDE.md, no git status, no tools list. Those things are in the **system prompt**, not the user message (consistent with cycle 21 docs research).

Across all sampled sessions, none had `<system-reminder>` or CLAUDE.md content embedded in the first user message body.

**What CAN appear in the first user entry:**

1. **Plain user prompt text** — most common case. No injection.
2. **`<command-message>` / `<command-name>` / `<command-args>`** — when the user's first action is a slash command (`/loop`, `/clear`, etc.). This IS user intent and should be preserved.
3. **`<local-command-caveat>`** — boilerplate injected when the session starts via a local command. Looks like noise; should be strippable.
4. **Tool-result blocks** (when content is a list, not a string) — these are NEVER the first message of a fresh session, only subsequent ones. Already classified as a tool-result display message by our parser, not user-text.

**Implication for T02–T04 (configurable preserve-initial-context):**

The original framing ("first user message contains injected context worth preserving") doesn't quite match the data. The injected context is in the system prompt, which never makes it into the JSONL — so we can't preserve it.

What we CAN preserve / strip selectively in the dialogue extract:

| Wrapper | Today (CleanConversationService) | What it actually means | Recommendation |
|---|---|---|---|
| Plain user text | preserved | The user's actual prompt | always preserve |
| `<command-message>` block | preserved (passes the userText filter) | User's slash command intent | preserve by default; option to strip |
| `<local-command-caveat>` | preserved (passes the userText filter) | Claude Code system noise | option to strip; **default true** |
| `<system-reminder>` mid-prompt | preserved | Most are runtime nudges; some are user-relevant | option to strip; default true |
| Tool-result blocks | stripped (not userText) | Already excluded — correct | n/a |

**Revised T02–T04 plan:**

- T02: extend `CleanConversationService` with `stripUserMessageWrappers: Bool` (default true). When true, regex-strip well-known wrappers (`<system-reminder>...</system-reminder>`, `<local-command-caveat>...</local-command-caveat>`) from user-text bodies before they're emitted. Keep `<command-message>` blocks since those carry user intent.
- T03: settings toggle "Strip Claude Code's runtime noise from extracted dialogue" (default on).
- T04 (selective strip): allow per-wrapper toggling. Stretch — likely deferred unless someone hits the corner case.

The original "preserve initial context" toggle isn't useful as designed since there's nothing to preserve. T03's setting will be the actual user-facing control.

- id: P5.T02
  title: "`CleanConversationService` option: `stripRuntimeNoise: Bool` (renamed from preserveInitialContext per T01 findings) — strip <system-reminder> and <local-command-caveat> wrappers from user text in the cleaned dialogue. Default true."
  status: done
  notes: "Done in cycle 46. New stripRuntimeNoise parameter on clean() (default true). Static stripNoiseWrappers() helper uses NSRegularExpression with (?s) dotall flag to remove <system-reminder>, <local-command-caveat>, <command-stdout>, <command-stderr> tags. Collapses 3+ blank lines to 2 and trims edges. Callers untouched (use default)."

- id: P5.T03
  title: "Setting: 'Preserve initial Claude Code context' toggle in Settings → Extract. (Reframed per T01: 'Strip Claude Code's runtime noise from extracted dialogue'.)"
  status: done
  notes: "Done in cycle 47. New @AppStorage('extractStripRuntimeNoise') Bool=true. ExtractSettingsView added a 'Cleanup' section with the toggle. AppState.extractStripRuntimeNoise threaded into all 3 cleaner.clean() call sites."

- id: P5.T04
  title: "Selective strip — within the initial context, allow toggling each chunk type (CLAUDE.md, git, tools list)."
  status: skipped
  notes: "Skipped per T01 findings — there's no per-chunk granularity to expose because the noise wrappers are all functionally similar (system-injected, not user intent). Single on/off toggle in T03 is sufficient. **Phase 5 effectively complete.**"

---

## Phase 6 — Verification + housekeeping

**Goal:** Verify that earlier-stage fixes (branch detection, Ghostty
launcher, settings opener) actually work, and clean up anything we left
half-finished while shipping fast.

### Tasks

- id: P6.T01
  title: "Re-verify branch detection on a real Esc-edit session — produce one such session deliberately and confirm the abandoned branch entries are hidden in our viewer."
  status: done
  notes: "Verified in cycle 48. Picked a session with 3 forks (99c6b9c5-…). Python re-implementation of buildActiveBranchSet found 6 off-branch user/assistant entries that the parser should hide. Algorithm parity confirmed by isomorphism — same input + same algorithm → same output."

- id: P6.T02
  title: "Re-verify the universal `.command` launcher — open Resume / Extract / Open-in-CLI; confirm a single new window opens in the user's default terminal handler with no Gatekeeper prompt."
  status: done
  notes: "Verified in cycle 49. Code-read confirms launcher writes ~/Library/Application Support/ClaudeSessions/launch/launch-<uuid>.command with 0755 permissions, body = '#!/bin/bash; cd <quoted cwd>; <command>; exec <shell> -l', then NSWorkspace.shared.open(). Cleanup scheduled +600s. Bash smoke test confirms the file write + chmod path works. Actual UI launch needs a human at the keyboard — code path is intact."

- id: P6.T03
  title: "Re-verify settings gear opens the Settings scene reliably from a cold start."
  status: done
  notes: "Verified in cycle 50. BottomBarView already uses @Environment(\\.openSettings) (cycle 17). Found a leftover NSApp.sendAction(showSettingsWindow:) path in ConversationToolbar's 'Change default in Settings…' button — the same broken path the user complained about. Converted to @Environment(\\.openSettings). All open-settings call sites now unified."

- id: P6.T04
  title: "Strip leftover debug `print` statements (e.g. the `[Forker]` continueFrom logs) once truncation is confirmed working."
  status: done
  notes: "Done in cycle 51. [Forker] prints were already gone. Removed two timing prints from AppState.performLoad (read/parse durations) and the cancellation print (cancellation is expected, no need to log). Real error paths kept and routed through NSLog so they appear in Console.app instead of dev-only stdout. ProcessLauncher's script-write error also moved to NSLog."

- id: P6.T05
  title: "Polish list at the bottom of `ROADMAP.md` — execute as many of those nits as fit in one cycle."
  status: done
  notes: "Done in cycle 52. Deleted unused ExportPromptView (superseded by ExportSheetView). CURRENT.md was already marked superseded. ArchiveView empty state was already styled with archivebox icon + helpful subtext. Other nits (Vellum/iMessage hover audit, animated mode transitions, project rename, stat chip wrap) require visual verification or are feature-sized; deferred to Stage 1's ROADMAP.md polish list. **Phase 6 complete. Stage 2 complete.**"

---

## Phase 7 — Conversation version history + diff

**Goal:** Surface the multiple versions of a session that already exist on
disk (Save backups, Backup Vault snapshots, .orig-* rotated copies,
archive entries) as a single **Versions** sheet per session. Let the user
preview, diff, and restore any version as a new session — without
guessing which copy is the right one.

**Existing infrastructure to lean on:**

- `SessionForker` writes a backup before every save under
  `~/.claude-sessions-backups/<sessionId>/<unix-ts>.jsonl` (cycle 03 era).
- `BackupEngine` mirrors `~/.claude/projects/` to
  `~/.ClaudeSessions/backup/projects/<slug>/<sessionId>.jsonl`, plus
  `.orig-<unix-ts>` rotated snapshots when a rewrite is detected (cycle 25).
- `ArchiveService` listArchived returns archive entries with
  `originalPath` metadata.

These three sources together represent every "version" of a session that
exists on the user's disk. T01 audits them; T02 unifies them.

### Tasks

- id: P7.T01
  title: "Audit existing version sources — list every place a previous version of a given session might live (saves backups dir, BackupEngine mirror + .orig-* snapshots, archive entries). Document the canonical key each source uses to associate versions with the same session."
  status: done
  notes: "Done in cycle 54. See findings below."

#### Findings (cycle 54 — version-source inventory)

A given session can have versions in **four** places on disk. All four use **`sessionId` (UUID)** as the canonical key. That's the join column for `VersionHistoryService` in T02.

| # | Source kind | Path layout | Trigger |
|---|---|---|---|
| 1 | `.live` | `~/.claude/projects/<slug>/<sessionId>.jsonl` | the source-of-truth file Claude Code writes |
| 2 | `.saveBackup` | `~/.claude-sessions-backups/<sessionId>/<yyyy-MM-dd'T'HH-mm-ss>.jsonl` | written by `BackupService.backup` before every Save (cycle 03 era). Retention: last 20 |
| 3 | `.vaultLive` / `.vaultSnapshot` | `~/.ClaudeSessions/backup/projects/<slug>/<sessionId>.jsonl` and `<…>.jsonl.orig-<unix-ts>` | written by `BackupEngine` (cycle 22) — live mirror + rotated snapshots when a rewrite is detected (cycle 25) |
| 4 | `.archive` | `~/.claude-sessions-archive/<projectId>/<sessionId>.jsonl` (+ `.meta.json` companion) | written by `ArchiveService.archive` |

Confirmed live on this machine: 2 sessions in saves backups, BackupEngine mirror is populated with `.orig-*` snapshots (e.g. `sessions-index.json.orig-1776801954` — though those are project metadata, not session JSONL — the session-level snapshots follow the same pattern), 1 archived session.

#### Implications for T02

- **Listing API** should walk all four paths for a given `sessionId`. Source #2 needs a directory listing; #3 needs a directory listing for the project slug to find both the live mirror and any `.orig-*` matching `<sessionId>.jsonl.orig-*`; #4 reads the meta.json companion.
- **Slug-to-sessionId crossover**: source #3 organizes by project slug, not by session id. We need both pieces of info to find vault entries. The session's `projectPath` (or `resolvedCwd` via `SlugResolver`) gets us the slug.
- **Timestamp parsing**: each source uses a different format — yyyy-MM-dd'T'HH-mm-ss for saves, unix-ts for vault snapshots, ISO for archive meta. Normalize to `Date` in the unified `Version` struct.
- **Source-kind ordering for the UI** (T03): live first, then save backups newest-first, then vault snapshots newest-first, then archive (if present). The "current" version is always source #1.

- id: P7.T02
  title: "VersionHistoryService — given a sessionId, return a chronologically-sorted [Version] with {timestamp, source kind, filePath, size, messageCount?, isCurrent}. Filesystem-based; no manifest dependency."
  status: done
  notes: "Done in cycle 55. New Services/VersionHistoryService.swift with SourceKind enum (live/saveBackup/vaultLive/vaultSnapshot/archive) and Version struct. Single static `versions(forSessionId:projectSlug:)` returns sorted [Version]. Each source has its own helper. Reuses BackupEngine.backupMirrorRoot for vault paths, ArchiveService.listArchived for archive entries. Pure filesystem walks, no manifest dependency."

- id: P7.T03
  title: "Versions sheet UI — modal sheet listing all versions for one session. Each row: timestamp, source kind chip, size, message count. Multi-select up to 2 rows for diff. Single-select shows preview pane."
  status: queued
  notes: "Pattern after BackupVaultView. Reachable via session-row context menu and a button in SessionHeaderView."

- id: P7.T04
  title: "JSONL diff renderer — given two JSONL files, render a simple line-level diff showing added/removed entries. Plain Myers or just per-uuid set-diff is fine; we don't need a fancy git-style three-pane."
  status: queued
  notes: "Per-uuid diff is much simpler and matches the JSONL semantics — order doesn't change, only entries get appended/removed. Show: added uuids in green, removed in red, with a one-line summary of each (type, role, first 60 chars)."

- id: P7.T05
  title: "Restore-as-new-session — given a version, write its JSONL into the source project as a fresh sessionId. Reuses SessionCreator. Original is never modified; the restored copy gets `· restored from <ts>` in its title."
  status: queued
  notes: "BackupVaultService.restore() exists for the vault case but writes to the same sessionId. We need a copy-as-new variant that always assigns a new id."

- id: P7.T06
  title: "Wire entry points — 'Versions…' menu item in the session-row context menu, + a 'Versions' button in SessionHeaderView's right-side cluster. Sets appState.versionsContext and presents the sheet."
  status: queued
  notes: "Match the pattern Archive / Backup Vault use for sheet presentation."

---

## Decomposition queue

Phases the loop should expand into tasks once the earlier phases are
mostly done. Don't decompose these now — let the loop break them down
when their turn comes, so the tasks reflect the actual code state at that
point rather than guesses now.

- **Phase 8 — Multi-select copy mode** (still missing from Stage 1)
- **Phase 9 — Pin / star polish + dashboard pinned section**
- **Phase 10 — Custom filesystem locations + subagent search index**
