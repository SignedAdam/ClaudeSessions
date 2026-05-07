# Cycle 32 — Embedded chat toggle (P2.T06) — Phase 2 complete

**Task:** Surface the existing `embeddedChatEnabled` `@AppStorage` flag as a Settings toggle.

## What I did

Added an "Embedded chat" section at the top of `ClaudeCodeSettingsView`. Single Toggle bound to `@AppStorage("embeddedChatEnabled")`, default true.

`ConversationContainerView` already reads the flag (cycle 28) — so the toggle takes effect immediately: turning it off hides the composer, turning it on shows it.

## Phase 2 status

All Phase 2 tasks are now done:

- T01 ✅ research (validated `claude -p --resume` appends to JSONL)
- T02 ✅ composer box at bottom of conversation
- T03 ✅ ClaudeRunner subprocess plumbing
- T04 ✅ live append rendering (diff + auto-scroll + fresh marker)
- T05 ✅ stop button while in-flight
- T06 ✅ enable/disable toggle

The user can now type a prompt in the composer at the bottom of any open conversation, hit ⌘↩ to send, see the assistant's response stream into the conversation view as `claude -p` writes to the JSONL, hit ⌘. (or click stop) to cancel mid-flight, and disable the whole thing in Settings → Claude Code if they prefer terminal-only.

## Build status

`swift build` clean.

## Files changed

- Edit: `Sources/ClaudeSessions/Views/Settings/ClaudeCodeSettingsView.swift`
- Edit: `docs/STAGE_2_ROADMAP.md` — T06 → done, **Phase 2 complete**
