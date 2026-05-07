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
  status: queued
  notes: "Visible only in Chat/Reading mode, not JSON. Hidden when no session is open."

- id: P2.T03
  title: "Subprocess plumbing — `ClaudeRunner` service that spawns `claude -p`, streams stdout/stderr, surfaces errors as toasts, captures the run's exit status."
  status: queued
  notes: "Pure `Process` API. No PTY needed for `-p` mode."

- id: P2.T04
  title: "Live append rendering — when the watched JSONL grows during a run, render the new entries with a subtle 'new' fade-in. Auto-scroll to bottom unless the user has scrolled up."
  status: queued
  notes: "FileWatcher already detects writes; need partial parse + diff-merge into displayMessages."

- id: P2.T05
  title: "Cancel run — a Stop button while the subprocess is alive. Sends SIGINT, then SIGTERM if it doesn't quit."
  status: queued
  notes: ""

- id: P2.T06
  title: "Setting: enable/disable embedded chat — for users who prefer to keep all interactive work in their terminal."
  status: queued
  notes: "Default on. Settings → Claude Code tab."

---

## Phase 3 — In-app MCP server (AI control)

**Goal:** Expose the app's operations as an MCP server that Claude Code (or
any MCP client) can call. So the user can type to Claude in their terminal:
"open the Stripe webhook conversation, extract the dialogue, and resume it
with my prompt 'continue from here'" — and Claude does it via our app.

### Tasks

- id: P3.T01
  title: "Decide MCP transport — stdio (spawned per-client) vs HTTP (long-running)."
  status: queued
  notes: "HTTP on localhost is friendlier for our case (we're already a long-running app). Document the choice."

- id: P3.T02
  title: "MCPServer skeleton — `Services/MCPServer.swift` that listens on a localhost port, parses JSON-RPC, dispatches to handlers."
  status: queued
  notes: "No external SDK. JSON-RPC 2.0 is small enough to implement directly."

- id: P3.T03
  title: "Tools: navigation — `list_projects`, `list_sessions(project_id)`, `open_session(session_id)`, `close_session()`."
  status: queued
  notes: ""

- id: P3.T04
  title: "Tools: read — `read_dialogue_only(session_id)`, `read_full_transcript(session_id)`, `read_session_metadata(session_id)`."
  status: queued
  notes: "Returns plain-text or structured data depending on the call."

- id: P3.T05
  title: "Tools: organize — `star`, `unstar`, `hide`, `unhide`, `archive`, `unarchive`, `move_to_project`, `delete_to_trash`."
  status: queued
  notes: ""

- id: P3.T06
  title: "Tools: launch — `extract_and_open(session_id, mode)`, `resume_in_terminal(session_id)`."
  status: queued
  notes: ""

- id: P3.T07
  title: "Setting: MCP server enable/disable + port + show the install instructions."
  status: queued
  notes: "Settings tab, with a 'copy snippet' button for the user's `~/.claude/settings.json` MCP config."

---

## Phase 4 — Settings UX overhaul

**Goal:** The settings popup currently looks unstyled and overflows.
Tabs cut off content. No scrolling. Make it feel like the rest of the app
and ensure every section is reachable at the default size.

### Tasks

- id: P4.T01
  title: "Audit every settings tab at the default 520×420 size — note every overflow case in the task body (Claude Code tab is known overflowing)."
  status: queued
  notes: "Output: list each tab × each viewport that breaks, with screenshots-by-description."

- id: P4.T02
  title: "Wrap every settings tab in a `ScrollView { … }` so any content fits, regardless of vertical size."
  status: queued
  notes: "Same wrapper for all tabs to keep consistency."

- id: P4.T03
  title: "Re-style settings tabs to match app theming — `Theme.surface` backgrounds, `Theme.text` for headings, `Theme.textSecondary` for body, no native white panel."
  status: queued
  notes: "Possibly drop `TabView` style in favor of a custom sidebar+detail two-pane layout for better hierarchy."

- id: P4.T04
  title: "Resize the settings window to 640×520 default with a min size that lets the longest tab fit without scrolling."
  status: queued
  notes: ""

- id: P4.T05
  title: "Section dividers + spacing pass on every tab — currently inconsistent."
  status: queued
  notes: ""

---

## Phase 5 — Configurable extract behavior

**Goal:** The `clean` extract currently strips ALL non-dialogue. The first
user message in a Claude Code session usually contains injected context
(CLAUDE.md, working directory, git branch). Stripping it loses important
priming. Make this user-configurable.

### Tasks

- id: P5.T01
  title: "Survey what Claude Code injects into the first user message — read the message bodies of the first user entry across several sessions on disk; classify the chunks (CLAUDE.md, system reminders, git status, tools list, etc.)."
  status: queued
  notes: "Output: a short note here describing the structure so we can selectively strip."

- id: P5.T02
  title: "`CleanConversationService` option: `preserveInitialContext: Bool` — when true, keep the first user entry's injected blocks intact; when false (current behavior), strip them. Default true."
  status: queued
  notes: ""

- id: P5.T03
  title: "Setting: 'Preserve initial Claude Code context' toggle in Settings → Extract."
  status: queued
  notes: "Default on. Help text explains what it does."

- id: P5.T04
  title: "Selective strip — within the initial context, allow toggling each chunk type (CLAUDE.md, git, tools list)."
  status: queued
  notes: "Stretch. Worth doing once T01 reveals what's actually there."

---

## Phase 6 — Verification + housekeeping

**Goal:** Verify that earlier-stage fixes (branch detection, Ghostty
launcher, settings opener) actually work, and clean up anything we left
half-finished while shipping fast.

### Tasks

- id: P6.T01
  title: "Re-verify branch detection on a real Esc-edit session — produce one such session deliberately and confirm the abandoned branch entries are hidden in our viewer."
  status: queued
  notes: ""

- id: P6.T02
  title: "Re-verify the universal `.command` launcher — open Resume / Extract / Open-in-CLI; confirm a single new window opens in the user's default terminal handler with no Gatekeeper prompt."
  status: queued
  notes: ""

- id: P6.T03
  title: "Re-verify settings gear opens the Settings scene reliably from a cold start."
  status: queued
  notes: ""

- id: P6.T04
  title: "Strip leftover debug `print` statements (e.g. the `[Forker]` continueFrom logs) once truncation is confirmed working."
  status: queued
  notes: ""

- id: P6.T05
  title: "Polish list at the bottom of `ROADMAP.md` — execute as many of those nits as fit in one cycle."
  status: queued
  notes: ""

---

## Decomposition queue

Phases the loop should expand into tasks once the earlier phases are
mostly done. Don't decompose these now — let the loop break them down
when their turn comes, so the tasks reflect the actual code state at that
point rather than guesses now.

- **Phase 7 — Conversation version history + diff** (deferred from Stage 1)
- **Phase 8 — Multi-select copy mode** (still missing from Stage 1)
- **Phase 9 — Pin / star polish + dashboard pinned section**
- **Phase 10 — Custom filesystem locations + subagent search index**
