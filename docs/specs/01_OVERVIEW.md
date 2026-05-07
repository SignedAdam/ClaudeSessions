# Claude Sessions — macOS App

## What This Is

A native macOS SwiftUI application for browsing, reading, editing, and managing Claude Code conversation histories. It reads the JSONL conversation files that Claude Code stores locally at `~/.claude/projects/`, presents them in a clean, familiar chat interface, and lets the user edit, fork, extract, and re-use conversations.

**App name:** Claude Sessions (working title, subject to change)

**Platform:** macOS 14+ (Sonoma). SwiftUI with AppKit integration where needed.

**License:** Open source. Designed for a single user's local machine.

## Why It Exists

Claude Code stores every conversation as a JSONL file. These files contain messages, tool calls, tool results, system metadata, file snapshots, and more. There is no built-in way to:

- Browse past conversations across projects
- Read them in a clean chat-like format
- Edit messages (yours or Claude's) to clean up a conversation
- Extract just the human-Claude dialogue (stripping tool calls, system noise) for re-use as context in a new session
- Search across conversations using natural language
- Copy formatted conversation excerpts for pasting elsewhere

This app solves all of that.

## Core Principles

1. **Read-first, edit-second.** The primary use is browsing and reading. Editing is available but never auto-saves. The user explicitly commits changes.
2. **Non-destructive.** Before any save/overwrite, the previous version is backed up automatically. The user can always go back.
3. **Familiar.** The conversation view looks like a chat app. No novel UI paradigms. macOS-native feel.
4. **Fast.** Conversations can be 4MB+ with 500+ entries. The app must not lag when loading or scrolling.
5. **Project-aware.** Conversations are grouped by the project directory they were started in, making it easy to find "that conversation I had while working on shortimize-backend."

## High-Level Feature Set

### v1 (This Spec)

- Browse all Claude Code conversations across all projects
- View conversations in a clean chat format with markdown rendering
- Toggle visibility of message types (user, assistant, tool calls, tool results, system)
- Copy individual messages or multi-select and copy with role/timestamp formatting
- Edit any message (user or Claude) in-place, with explicit save
- JSON mode — view/edit the raw JSONL
- "Export as prompt" — extract just the human+Claude text dialogue, formatted for pasting into a new chat
- "Start new session" — open Claude Code CLI with a selected conversation loaded as context
- Automatic backup before saves
- Right-click context menus on messages
- AI-powered search across conversations (BYOK via OpenRouter)
- Settings: OpenRouter API key, preferred model, theme

### Future (Not This Spec)

- Version history with diff view
- Conversation merging
- Tagging / bookmarking
- Linux port (GTK or Electron fallback)
