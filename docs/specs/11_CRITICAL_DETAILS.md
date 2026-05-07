# Critical Implementation Details

## Lossless Round-Tripping

This is the MOST IMPORTANT implementation detail. When the user saves a modified conversation, every JSONL line that was NOT modified must be written back **byte-for-byte identical** to the original. This prevents data loss and ensures Claude Code can still read the file.

### Strategy

1. **On parse:** For each JSONL line, store the raw JSON string alongside the decoded struct:
   ```swift
   struct IndexedEntry {
       let index: Int          // line number in the file
       let rawJSON: String     // the original line, byte-for-byte
       var entry: RawEntry     // the decoded struct
       var isModified: Bool    // whether the user changed this entry
       var isDeleted: Bool     // whether the user marked this for deletion
   }
   ```

2. **On write:**
   ```swift
   func write(entries: [IndexedEntry], to path: URL) throws {
       var lines: [String] = []
       for entry in entries {
           if entry.isDeleted { continue }
           if entry.isModified {
               // Re-serialize from the struct
               let data = try JSONEncoder().encode(entry.entry)
               lines.append(String(data: data, encoding: .utf8)!)
           } else {
               // Use the original raw JSON verbatim
               lines.append(entry.rawJSON)
           }
       }
       let content = lines.joined(separator: "\n") + "\n"
       // Atomic write
       try content.write(to: tempPath, atomically: true, encoding: .utf8)
       try FileManager.default.moveItem(at: tempPath, to: path)
   }
   ```

3. **What counts as "modified":**
   - User edited the message text (chat mode)
   - User edited the raw JSON (JSON mode)
   - **NOT** modified: entries that were merely read and displayed. Even if our decoder doesn't capture every field, the raw string preserves everything.

### Why This Matters
Claude Code's JSONL format evolves. New fields get added. If we decode→encode every line, we'll drop unknown fields. Preserving raw JSON for unmodified entries means we're forward-compatible with any future format changes.

## Message Display Order

Messages are displayed in **file order** (line 1, line 2, line 3...), NOT by threading (parentUuid chains).

The `parentUuid` field is NOT used for display ordering. It exists for Claude Code's internal state management. The JSONL file is already in chronological order.

The parser simply iterates lines top-to-bottom and builds the display list. Skip non-message entries (file-history-snapshot, progress, queue-operation, last-prompt, etc.).

## Tool Call ↔ Tool Result Pairing

### Algorithm
When building the display list:

1. Maintain a map: `pendingToolCalls: [String: ToolCallMessage]` keyed by `tool_use` block `id`
2. For each assistant entry with `tool_use` blocks:
   - Create a `ToolCallMessage` for each block
   - Add to `pendingToolCalls[block.id]`
3. For each user entry with `tool_result` blocks:
   - For each tool_result block, look up `pendingToolCalls[block.tool_use_id]`
   - If found: create a `ToolInteraction` pairing them, remove from pending
   - If not found: create a standalone `ToolResultMessage`
4. At the end, any remaining entries in `pendingToolCalls` become standalone `ToolCallMessage`s (tool was called but no result recorded — can happen if the session was interrupted)

### Display Grouping
A `ToolInteraction` renders as a single card with both the call and result inside it:

```
┌─ Tool: Bash — List dev directory contents ─── 5:03 PM ─┐
│ ▶ ls -la /Users/sauel/dev                              │ ← collapsed call
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ▶ total 128 drwxr-xr-x 24 sauel staff 768 Apr 5...    │ ← collapsed result
└─────────────────────────────────────────────────────────┘
```

Both sections independently expand/collapse. The divider between them is a dashed line.

## Project Name Derivation

The directory slug encodes the full filesystem path:
```
-Users-sauel-dev-shortimize-backend  →  /Users/sauel/dev/shortimize-backend
```

To get a human-readable name:

1. **Preferred:** If `sessions-index.json` exists and has `originalPath`, use the last path component:
   - `originalPath: "/Users/sauel/dev/shortimize-backend"` → `"shortimize-backend"`
   - `originalPath: "/Users/sauel/dev"` → `"dev"`
   - `originalPath: "/Users/sauel"` → `"~ (home)"`

2. **Fallback:** Parse the slug:
   - Remove the leading `-`
   - Replace `-` with `/`
   - This gives an approximation of the path (not perfect — directory names with hyphens are ambiguous)
   - Take the last path component
   - Special case: if the result is the user's home directory, show `"~ (home)"`

3. **Display:** Show the full original path as a tooltip on hover.

## Display Name Configuration

- Default display name: `"You"` (neutral, works for anyone)
- Configurable in Settings → General → "Display Name"
- Stored in `UserDefaults` as `displayName`
- Used in:
  - Message headers for user messages
  - Copy formatting: `[<displayName> — 5:02 PM]`
  - Export as prompt: `[<displayName>]` or `[User]` (user's choice)

## Conversation Stats Calculation

Only count entries that are actual messages:

| Stat | Counts |
|------|--------|
| User messages | `type: "user"` where `message.content` is a String AND `isCompactSummary` is not true |
| Claude messages | `type: "assistant"` entries that contain at least one `text` block AND `isApiErrorMessage` is not true |
| Tool calls | Total number of `tool_use` blocks across all assistant entries |
| System messages | `type: "system"` entries (all subtypes) |
| Duration | Last timestamp minus first timestamp (across ALL entries, not just messages) |

## File Watching with FSEvents

Use `DispatchSource.makeFileSystemObjectSource` to watch the conversation file for changes:

```swift
class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    
    func watch(path: String, onChange: @escaping () -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        
        source?.setEventHandler { onChange() }
        source?.setCancelHandler { close(fd) }
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
    }
}
```

When a change is detected:
- If the conversation is not dirty: silently reload
- If dirty: show a non-modal banner at the top: "This file was modified externally. [Reload] [Ignore]"

## Handling the `conversation.html` Build Artifact

Add to `.gitignore`:
```
conversation.html
```

This file is a 4MB generated artifact from the prototype HTML viewer. It should not be committed.

## Keychain Storage for API Keys

Use the Security framework directly (no KeychainAccess package):

```swift
import Security

enum KeychainService {
    static let service = "com.claude-sessions.openrouter"
    
    static func save(key: String) throws {
        let data = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)  // delete existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

## Terminal Launch for "Open in Claude Code"

```swift
import AppKit

enum ProcessLauncher {
    static func openInTerminal(command: String, directory: String) {
        // Try iTerm2 first, then Terminal.app
        if let iterm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
            let script = """
            tell application "iTerm2"
                create window with default profile command "cd \(directory) && \(command)"
            end tell
            """
            runAppleScript(script)
        } else {
            let script = """
            tell application "Terminal"
                do script "cd \(directory) && \(command)"
                activate
            end tell
            """
            runAppleScript(script)
        }
    }
    
    private static func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
}
```

Note: Requires "Automation" permission in System Settings → Privacy & Security for the app to control Terminal/iTerm2 via AppleScript.
