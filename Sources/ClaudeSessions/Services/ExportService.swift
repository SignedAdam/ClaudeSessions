import Foundation
import CryptoKit

/// Export a conversation to one of several portable formats.
///
/// Markdown / JSON are general-purpose. Codex / Gemini produce files in
/// the wire formats those CLIs use, so the export can be dropped into the
/// right directory and resumed.
///
/// All exporters apply pending edits and skip deletions, like the rest of
/// the editing pipeline.
enum ExportService {

    // MARK: - Format identifiers

    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case json
        case codex
        case gemini
        case opencode
        case cursor
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .markdown: return "Markdown"
            case .json:     return "JSON"
            case .codex:    return "Codex CLI"
            case .gemini:   return "Gemini CLI"
            case .opencode: return "opencode"
            case .cursor:   return "Cursor"
            }
        }

        /// Whether this format has a meaningful "include tool calls" toggle.
        /// Codex/Gemini format files always need to look complete, so the
        /// toggle is only exposed for markdown/json where omission is safe.
        var supportsToolToggle: Bool {
            switch self {
            case .markdown, .json:                              return true
            case .codex, .gemini, .opencode, .cursor:           return false
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown:  return "md"
            case .json:      return "json"
            case .codex:     return "jsonl"
            case .gemini:    return "json"
            case .opencode:  return "md"
            case .cursor:    return "md"
            }
        }
    }

    // MARK: - Result

    struct Result {
        /// The serialized export content (UTF-8 string).
        let content: String
        /// A suggested filename, no path.
        let suggestedFilename: String
        /// For Codex/Gemini, an absolute directory path where the CLI expects
        /// the file to live. nil for Markdown/JSON which are generic.
        let suggestedDirectory: String?
        /// Counts of what made it into the output (for the toast/UI).
        let messageCount: Int
        let toolCallCount: Int
    }

    // MARK: - Public entry point

    static func export(
        format: Format,
        conversation: Conversation,
        title: String,
        includeTools: Bool,
        displayName: String,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> Result {
        switch format {
        case .markdown:
            return exportMarkdown(
                conversation: conversation,
                title: title,
                includeTools: includeTools,
                displayName: displayName,
                editedTexts: editedTexts,
                deletedMessageIds: deletedMessageIds
            )
        case .json:
            return exportJSON(
                conversation: conversation,
                title: title,
                includeTools: includeTools,
                editedTexts: editedTexts,
                deletedMessageIds: deletedMessageIds
            )
        case .codex:
            return exportCodex(
                conversation: conversation,
                title: title,
                editedTexts: editedTexts,
                deletedMessageIds: deletedMessageIds
            )
        case .gemini:
            return exportGemini(
                conversation: conversation,
                title: title,
                editedTexts: editedTexts,
                deletedMessageIds: deletedMessageIds
            )
        case .opencode:
            return exportContinuationMarkdown(
                conversation: conversation,
                title: title,
                agentName: "opencode",
                displayName: displayName,
                editedTexts: editedTexts,
                deletedMessageIds: deletedMessageIds
            )
        case .cursor:
            return exportContinuationMarkdown(
                conversation: conversation,
                title: title,
                agentName: "Cursor",
                displayName: displayName,
                editedTexts: editedTexts,
                deletedMessageIds: deletedMessageIds
            )
        }
    }

    // MARK: - Generic continuation markdown
    //
    // For agents without a session-restore wire format (opencode TUI,
    // Cursor IDE), we emit a clean markdown transcript prefixed with a
    // "continue this conversation" header. The user pastes/opens it in
    // the target agent and asks it to pick up where Claude left off.
    private static func exportContinuationMarkdown(
        conversation: Conversation,
        title: String,
        agentName: String,
        displayName: String,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> Result {
        var msgCount = 0
        var out = ""
        out += "# Continuing a Claude conversation in \(agentName)\n\n"
        out += "I had the following conversation with Claude. Please read the full thread and pick up exactly where we left off — same goals, same constraints, no need to summarize.\n\n"
        if let cwd = conversation.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd {
            out += "**Working directory:** `\(cwd)`\n\n"
        }
        out += "---\n\n"

        for msg in conversation.displayMessages {
            if deletedMessageIds.contains(msg.id) { continue }
            switch msg {
            case .userText(let m):
                if m.isCompactSummary { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                out += "## \(displayName)\n\n\(text)\n\n"
                msgCount += 1
            case .assistantText(let m):
                if m.isApiError { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                out += "## Claude\n\n\(text)\n\n"
                msgCount += 1
            default:
                continue
            }
        }

        let safeTitle = sanitizeFilename(title)
        return Result(
            content: out,
            suggestedFilename: "\(safeTitle)-for-\(agentName.lowercased()).md",
            suggestedDirectory: nil,
            messageCount: msgCount,
            toolCallCount: 0
        )
    }

    // MARK: - Markdown

    private static func exportMarkdown(
        conversation: Conversation,
        title: String,
        includeTools: Bool,
        displayName: String,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> Result {
        var out = ""
        var msgCount = 0
        var toolCount = 0

        // Header
        out += "# \(title)\n\n"
        if let cwd = conversation.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd {
            out += "**Project:** `\(cwd)`  \n"
        }
        if let model = conversation.rawEntries.compactMap({ $0.entry.message?.model }).first {
            out += "**Model:** `\(model)`  \n"
        }
        if let first = conversation.displayMessages.first?.timestamp {
            out += "**Started:** \(DateFormatting.dateString(first))  \n"
        }
        if let last = conversation.displayMessages.last?.timestamp {
            out += "**Last:** \(DateFormatting.dateString(last))  \n"
        }
        out += "\n---\n\n"

        for msg in conversation.displayMessages {
            if deletedMessageIds.contains(msg.id) { continue }

            switch msg {
            case .userText(let m):
                if m.isCompactSummary { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let ts = m.timestamp.map { " · \(DateFormatting.timeString($0))" } ?? ""
                out += "## \(displayName)\(ts)\n\n"
                out += "\(text)\n\n"
                msgCount += 1

            case .assistantText(let m):
                if m.isApiError { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let ts = m.timestamp.map { " · \(DateFormatting.timeString($0))" } ?? ""
                let model = m.model.map { " *(\($0))*" } ?? ""
                out += "## Claude\(ts)\(model)\n\n"
                out += "\(text)\n\n"
                msgCount += 1

            case .toolInteraction(let interaction):
                if !includeTools { continue }
                out += renderToolInteractionMarkdown(interaction)
                toolCount += 1

            case .toolCall(let m):
                if !includeTools { continue }
                out += renderToolCallMarkdown(m)
                toolCount += 1

            case .toolResult(let m):
                if !includeTools { continue }
                out += renderToolResultMarkdown(m)

            case .systemMessage(let m):
                if !includeTools { continue }
                out += "> _system · \(m.subtype)_  \n> \(m.content.replacingOccurrences(of: "\n", with: "\n> "))\n\n"

            case .compactBoundary(_):
                out += "---\n\n*Conversation compacted here.*\n\n---\n\n"
            }
        }

        let safeTitle = sanitizeFilename(title)
        return Result(
            content: out,
            suggestedFilename: "\(safeTitle).md",
            suggestedDirectory: nil,
            messageCount: msgCount,
            toolCallCount: toolCount
        )
    }

    private static func renderToolInteractionMarkdown(_ x: ToolInteraction) -> String {
        var out = ""
        out += renderToolCallMarkdown(x.toolCall)
        if let r = x.toolResult {
            out += renderToolResultMarkdown(r)
        }
        return out
    }

    private static func renderToolCallMarkdown(_ m: ToolCallMessage) -> String {
        let lang = languageHint(for: m.toolName)
        var out = "### \u{1F527} \(m.toolName) — \(m.summary)\n\n"
        // Render input as fenced code block. Pretty-print JSON if possible.
        let inputDisplay = prettyJSON(m.input) ?? String(describing: m.input)
        out += "```\(lang)\n\(inputDisplay)\n```\n\n"
        return out
    }

    private static func renderToolResultMarkdown(_ m: ToolResultMessage) -> String {
        let label = m.isError ? "result · error" : "result"
        var text = m.resultText
        // Cap result blocks so a runaway tool output doesn't dominate the file
        let cap = 10_000
        if text.count > cap {
            text = String(text.prefix(cap)) + "\n\n…[truncated, \(text.count - cap) chars]"
        }
        return "```output \(label)\n\(text)\n```\n\n"
    }

    private static func languageHint(for toolName: String) -> String {
        switch toolName {
        case "Bash": return "bash"
        case "Read", "Edit", "Write": return ""  // raw text args, code fences without lang look cleanest
        default: return "json"
        }
    }

    private static func prettyJSON(_ obj: [String: Any]) -> String? {
        guard let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return s
    }

    // MARK: - JSON

    private static func exportJSON(
        conversation: Conversation,
        title: String,
        includeTools: Bool,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> Result {
        var msgCount = 0
        var toolCount = 0
        var messages: [[String: Any]] = []

        for msg in conversation.displayMessages {
            if deletedMessageIds.contains(msg.id) { continue }

            switch msg {
            case .userText(let m):
                if m.isCompactSummary { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                var obj: [String: Any] = [
                    "role": "user",
                    "text": text
                ]
                if let ts = m.timestamp { obj["timestamp"] = ISO8601DateFormatter().string(from: ts) }
                messages.append(obj)
                msgCount += 1

            case .assistantText(let m):
                if m.isApiError { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                var obj: [String: Any] = [
                    "role": "assistant",
                    "text": text
                ]
                if let ts = m.timestamp { obj["timestamp"] = ISO8601DateFormatter().string(from: ts) }
                if let model = m.model { obj["model"] = model }
                messages.append(obj)
                msgCount += 1

            case .toolInteraction(let x):
                if !includeTools { continue }
                var obj: [String: Any] = [
                    "role": "tool_call",
                    "name": x.toolCall.toolName,
                    "summary": x.toolCall.summary,
                    "input": x.toolCall.input
                ]
                if let r = x.toolResult {
                    obj["result"] = [
                        "text": r.resultText,
                        "isError": r.isError
                    ]
                }
                if let ts = x.toolCall.timestamp { obj["timestamp"] = ISO8601DateFormatter().string(from: ts) }
                messages.append(obj)
                toolCount += 1

            case .toolCall(let m):
                if !includeTools { continue }
                var obj: [String: Any] = [
                    "role": "tool_call",
                    "name": m.toolName,
                    "summary": m.summary,
                    "input": m.input
                ]
                if let ts = m.timestamp { obj["timestamp"] = ISO8601DateFormatter().string(from: ts) }
                messages.append(obj)
                toolCount += 1

            case .toolResult(let m):
                if !includeTools { continue }
                var obj: [String: Any] = [
                    "role": "tool_result",
                    "text": m.resultText,
                    "isError": m.isError
                ]
                if let ts = m.timestamp { obj["timestamp"] = ISO8601DateFormatter().string(from: ts) }
                messages.append(obj)

            case .systemMessage(let m):
                if !includeTools { continue }
                var obj: [String: Any] = [
                    "role": "system",
                    "subtype": m.subtype,
                    "text": m.content
                ]
                if let ts = m.timestamp { obj["timestamp"] = ISO8601DateFormatter().string(from: ts) }
                messages.append(obj)

            case .compactBoundary(_):
                messages.append(["role": "compact_boundary"])
            }
        }

        var session: [String: Any] = [
            "id": conversation.sessionId,
            "title": title,
            "messages": messages
        ]
        if let cwd = conversation.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd {
            session["cwd"] = cwd
        }
        if let model = conversation.rawEntries.compactMap({ $0.entry.message?.model }).first {
            session["model"] = model
        }

        let root: [String: Any] = ["session": session]
        let json = serializeJSONPretty(root) ?? "{}"

        let safeTitle = sanitizeFilename(title)
        return Result(
            content: json,
            suggestedFilename: "\(safeTitle).json",
            suggestedDirectory: nil,
            messageCount: msgCount,
            toolCallCount: toolCount
        )
    }

    // MARK: - Codex CLI

    /// Codex stores sessions at `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO>-<sessionId>.jsonl`.
    /// Each line is `{timestamp, type, payload}`. We emit:
    ///   - one `session_meta` line
    ///   - one `response_item` + `event_msg` pair per message
    ///
    /// Tool calls are intentionally omitted: Claude's tool schema doesn't
    /// match Codex's, so a faithful round-trip would require re-running
    /// the work. The cleaned dialogue still resumes successfully.
    private static func exportCodex(
        conversation: Conversation,
        title: String,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> Result {
        _ = title  // not embedded in Codex format; reserved for future use
        let sessionId = generateCodexSessionId()
        let now = Date()
        let cwd = conversation.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path

        var lines: [String] = []
        var msgCount = 0

        // session_meta
        let metaPayload: [String: Any] = [
            "id": sessionId,
            "timestamp": iso8601(now),
            "cwd": cwd,
            "originator": "claude-sessions-app",
            "cli_version": "0.0.0",
            "instructions": NSNull()
        ]
        lines.append(serializeJSON([
            "timestamp": iso8601(now),
            "type": "session_meta",
            "payload": metaPayload
        ]) ?? "")

        for msg in conversation.displayMessages {
            if deletedMessageIds.contains(msg.id) { continue }

            switch msg {
            case .userText(let m):
                if m.isCompactSummary { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let ts = m.timestamp.map { iso8601($0) } ?? iso8601(now)

                let respItem: [String: Any] = [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": text]]
                ]
                lines.append(serializeJSON([
                    "timestamp": ts,
                    "type": "response_item",
                    "payload": respItem
                ]) ?? "")

                let eventMsg: [String: Any] = [
                    "type": "user_message",
                    "message": text
                ]
                lines.append(serializeJSON([
                    "timestamp": ts,
                    "type": "event_msg",
                    "payload": eventMsg
                ]) ?? "")

                msgCount += 1

            case .assistantText(let m):
                if m.isApiError { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let ts = m.timestamp.map { iso8601($0) } ?? iso8601(now)

                let respItem: [String: Any] = [
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": text]]
                ]
                lines.append(serializeJSON([
                    "timestamp": ts,
                    "type": "response_item",
                    "payload": respItem
                ]) ?? "")

                let eventMsg: [String: Any] = [
                    "type": "agent_message",
                    "message": text
                ]
                lines.append(serializeJSON([
                    "timestamp": ts,
                    "type": "event_msg",
                    "payload": eventMsg
                ]) ?? "")

                msgCount += 1

            default:
                continue  // tool calls/system not exported to Codex
            }
        }

        let content = lines.joined(separator: "\n") + "\n"

        // Suggested directory: `~/.codex/sessions/YYYY/MM/DD/`
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        let yyyy = String(format: "%04d", comps.year ?? 1970)
        let mm = String(format: "%02d", comps.month ?? 1)
        let dd = String(format: "%02d", comps.day ?? 1)
        let suggestedDir = "\(NSHomeDirectory())/.codex/sessions/\(yyyy)/\(mm)/\(dd)"

        // Filename: rollout-2026-04-25T12-34-56-<sessionId>.jsonl
        let isoFile = iso8601Compact(now)
        let filename = "rollout-\(isoFile)-\(sessionId).jsonl"

        return Result(
            content: content,
            suggestedFilename: filename,
            suggestedDirectory: suggestedDir,
            messageCount: msgCount,
            toolCallCount: 0
        )
    }

    /// Codex uses UUIDv7-like lowercase IDs (e.g. 019caffe-b4b0-7d91-9a02-942d2c98ab4e).
    /// A standard v4 UUID lowercased works for our purposes — Codex doesn't
    /// validate the version.
    private static func generateCodexSessionId() -> String {
        UUID().uuidString.lowercased()
    }

    // MARK: - Gemini CLI

    /// Gemini stores chats at `~/.gemini/tmp/<projectHash>/chats/session-<ISO>-<sessionId8>.json`.
    /// projectHash is SHA-256 of the project directory path.
    /// File is one big JSON object with `sessionId`, `projectHash`, `messages`, etc.
    private static func exportGemini(
        conversation: Conversation,
        title: String,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> Result {
        _ = title  // Gemini format also doesn't embed a session title
        let sessionId = UUID().uuidString.lowercased()
        let now = Date()
        let cwd = conversation.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let projectHash = sha256(cwd)

        var msgCount = 0
        var messages: [[String: Any]] = []

        for msg in conversation.displayMessages {
            if deletedMessageIds.contains(msg.id) { continue }

            switch msg {
            case .userText(let m):
                if m.isCompactSummary { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let ts = m.timestamp ?? now
                messages.append([
                    "id": UUID().uuidString.lowercased(),
                    "timestamp": iso8601(ts),
                    "type": "user",
                    "content": [["text": text]]
                ])
                msgCount += 1

            case .assistantText(let m):
                if m.isApiError { continue }
                let text = editedTexts[m.id] ?? m.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let ts = m.timestamp ?? now
                messages.append([
                    "id": UUID().uuidString.lowercased(),
                    "timestamp": iso8601(ts),
                    "type": "gemini",
                    "content": text,
                    "thoughts": [] as [Any],
                    "model": m.model ?? "claude-export"
                ])
                msgCount += 1

            default:
                continue  // tool calls intentionally not converted
            }
        }

        let firstTs = conversation.displayMessages.first?.timestamp ?? now
        let lastTs = conversation.displayMessages.last?.timestamp ?? now

        let root: [String: Any] = [
            "sessionId": sessionId,
            "projectHash": projectHash,
            "startTime": iso8601(firstTs),
            "lastUpdated": iso8601(lastTs),
            "messages": messages,
            "kind": "main"
        ]

        let content = serializeJSONPretty(root) ?? "{}"

        // Suggested location
        let suggestedDir = "\(NSHomeDirectory())/.gemini/tmp/\(projectHash)/chats"

        // Filename: session-2026-04-25T12-34-<sessionId8>.json
        let shortId = String(sessionId.prefix(8))
        let isoShort = iso8601Short(now)
        let filename = "session-\(isoShort)-\(shortId).json"

        return Result(
            content: content,
            suggestedFilename: filename,
            suggestedDirectory: suggestedDir,
            messageCount: msgCount,
            toolCallCount: 0
        )
    }

    // MARK: - Shared helpers

    private static func sanitizeFilename(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = s.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "conversation" : String(trimmed.prefix(80))
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// `2026-04-25T12-34-56` (Codex-style filename-safe)
    private static func iso8601Compact(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f.string(from: date)
    }

    /// `2026-04-25T12-34` (Gemini-style)
    private static func iso8601Short(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm"
        return f.string(from: date)
    }

    private static func sha256(_ s: String) -> String {
        let data = Data(s.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func serializeJSON(_ obj: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: d, encoding: .utf8)
    }

    private static func serializeJSONPretty(_ obj: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: d, encoding: .utf8)
    }
}
