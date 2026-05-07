# Edge Cases & Error Handling

## Data Parsing

### Malformed JSONL lines
- **Behavior:** Skip the line, log a warning. Do not crash.
- **UI:** If >10% of lines are malformed, show a warning banner: "Some entries in this conversation could not be parsed."

### Unknown entry types
- **Behavior:** Preserve in `rawEntries` (for round-trip), but don't add to `displayMessages`.
- **New types added by future Claude Code versions:** The app must not break when encountering unknown types.

### Missing fields
- **Behavior:** All fields are optional in the model. Missing fields get `nil`.
- **UI:** If a message has no timestamp, show nothing (don't show "Invalid Date"). If a user message has no content, show "[empty message]" in muted text.

### Empty JSONL files
- **Behavior:** Show empty state: "This conversation file is empty."

### Very large files (>10MB)
- **Behavior:** Still load into memory (10MB is fine). Show a loading indicator.
- **Performance:** Use `LazyVStack` for rendering. Don't render all markdown upfront — render on appear.

### Duplicate messages
- Some conversations have duplicate user messages (retries — same content, different UUIDs, close timestamps). 
- **Behavior:** Show both. Don't try to deduplicate. The user can delete one if they want.

### Compact summaries
- Messages with `isCompactSummary: true` are auto-generated context summaries, not real user messages.
- **Behavior:** Show with distinct styling: gray background, italic, "Context Summary" label, collapsible.
- **In export:** Exclude by default (but user can check the box to include).

## File System

### Permission denied
- **Behavior:** Show error in sidebar for that project: "Cannot access: permission denied."
- **Don't crash.** Continue loading other projects.

### Files deleted while app is open
- **Behavior:** If the user selects a deleted session, show: "This conversation file no longer exists."
- `FileWatcher` should detect deletions and update the sidebar.

### Files modified externally (e.g., by an active Claude Code session)
- **Behavior:** `FileWatcher` detects the change. If the conversation is currently viewed and not dirty, silently reload. If dirty, show: "This file was modified externally. Reload (discard your changes) / Keep your changes?"

### Symlinks
- **Behavior:** Follow symlinks when scanning. Don't special-case them.

## Editing

### Editing a message that references tool results
- If the user deletes a user text message, tool results remain (they're separate entries).
- If the user deletes a tool_use, also delete the corresponding tool_result (by matching `tool_use_id`).

### Editing markdown that breaks rendering
- The user might type invalid markdown. That's fine — just render what we can. Don't validate markdown on edit.

### Empty message after edit
- If the user clears a message entirely, allow it. Show "[empty message]" in the rendered view.

### Concurrent edits
- Only one message can be in edit mode at a time. Starting an edit on another message auto-commits the current one (applies the change to in-memory model, exits edit mode).

### Save conflicts
- If the file was modified externally between when we loaded it and when we save:
  1. Detect by comparing file modification date
  2. Show dialog: "This file was modified since you loaded it. Overwrite / Cancel / Reload?"
  3. If overwrite: backup the current file, then write our version
  4. The backup ensures no data is lost either way

## JSON Mode

### Lines that aren't valid JSON
- On load: skip them, show a warning.
- On edit: if the user introduces invalid JSON, highlight the line red and prevent save until fixed.
- The user can manually fix the JSON or undo their edit.

### Very long JSON lines
- Some entries (file-history-snapshot with many tracked files) can be 10,000+ characters on a single line.
- **Behavior:** The text editor should handle this with horizontal scrolling or word wrap (user preference).

## AI Search

### No API key
- **Behavior:** Show "Configure your OpenRouter API key in Settings to use AI search."
- Text search still works without API key.

### API rate limit / error
- Show the error message from the API.
- Don't retry automatically. Let the user retry manually.

### Model returns unexpected format
- If the model doesn't return valid JSON array of session IDs: show "Search returned unexpected results. Try a different query."

### Timeout
- 30-second timeout on API calls.
- Show "Search timed out. Try a simpler query."

## Copy

### Very long messages
- Copy the full text regardless of length. No truncation.

### Messages with images (attachments)
- Don't include image data in text copy. Show "[Image attachment]" as a placeholder.

### Tool results with binary/non-text content
- Copy as-is. It's the user's responsibility to interpret.

## Open in Claude Code

### Claude Code not installed
- Check if `claude` is in PATH. If not, show: "Claude Code CLI not found. Install it from https://claude.ai/code or set the path in Settings."

### Terminal app not found
- Default to Terminal.app. If that fails, show the command and let the user run it manually.

### Session no longer exists in Claude Code
- `claude --resume` may fail if the session was cleaned up. The user will see the error in the terminal.
