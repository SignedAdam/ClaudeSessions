import Foundation

/// Produces a "cleaned" version of a conversation: only user text + assistant text,
/// with all tool_use/tool_result/system/file-history/progress entries removed.
///
/// The output is a brand-new JSONL string with:
///   - A fresh sessionId on every entry
///   - Fresh UUIDs on every entry, with parentUuid chain rebuilt in order
///   - User edits applied from editedTexts
///   - Assistant content arrays stripped to just text blocks
///   - stop_reason adjusted from "tool_use" to "end_turn" where needed
///
/// This is not a conversation compaction. It's dialogue extraction — it
/// preserves the continuity of the human ↔ Claude thread while stripping
/// everything that was incidental to the original working session.
struct CleanConversationService {

    struct CleanResult {
        /// JSONL content, ready to write to disk
        let jsonl: String
        /// The new session UUID (matches sessionId in every entry)
        let sessionId: String
        /// Number of user text entries retained
        let userCount: Int
        /// Number of assistant text entries retained
        let assistantCount: Int
        /// Plain-text version of the conversation (for piped-prompt mode or clipboard)
        let plainText: String
    }

    /// Build a cleaned version of the conversation.
    ///
    /// - Parameters:
    ///   - conversation: The source conversation
    ///   - editedTexts: Pending user edits from AppState
    ///   - displayName: User's display name (for plain-text output)
    /// - Returns: CleanResult with the generated JSONL, new session ID, and plain text
    func clean(
        conversation: Conversation,
        editedTexts: [String: String] = [:],
        deletedMessageIds: Set<String> = [],
        displayName: String = "You",
        stripRuntimeNoise: Bool = true
    ) -> CleanResult {
        let newSessionId = UUID().uuidString.lowercased()
        var jsonlLines: [String] = []
        var plainTextParts: [String] = []
        var lastKeptUuid: String? = nil
        var userCount = 0
        var assistantCount = 0

        // Build a quick lookup: entryIndex -> [displayMessages at that index]
        // so we can find the right edit for each raw entry
        var displayByEntryIndex: [Int: [DisplayMessage]] = [:]
        for msg in conversation.displayMessages {
            let idx = msg.entryIndex
            displayByEntryIndex[idx, default: []].append(msg)
        }

        for indexed in conversation.rawEntries {
            guard let dict = parseJSON(indexed.rawJSON) else { continue }
            let type = dict["type"] as? String ?? ""

            switch type {
            case "user":
                guard let cleaned = processUserEntry(
                    dict: dict,
                    entryIndex: indexed.index,
                    newSessionId: newSessionId,
                    parentUuid: lastKeptUuid,
                    displayMessages: displayByEntryIndex[indexed.index] ?? [],
                    editedTexts: editedTexts,
                    deletedMessageIds: deletedMessageIds,
                    stripRuntimeNoise: stripRuntimeNoise
                ) else { continue }

                if let json = serializeJSON(cleaned.dict) {
                    jsonlLines.append(json)
                    lastKeptUuid = cleaned.newUuid
                    userCount += 1
                    plainTextParts.append("[\(displayName)]\n\(cleaned.text)")
                }

            case "assistant":
                guard let cleaned = processAssistantEntry(
                    dict: dict,
                    entryIndex: indexed.index,
                    newSessionId: newSessionId,
                    parentUuid: lastKeptUuid,
                    displayMessages: displayByEntryIndex[indexed.index] ?? [],
                    editedTexts: editedTexts,
                    deletedMessageIds: deletedMessageIds
                ) else { continue }

                if let json = serializeJSON(cleaned.dict) {
                    jsonlLines.append(json)
                    lastKeptUuid = cleaned.newUuid
                    assistantCount += 1
                    plainTextParts.append("[Claude]\n\(cleaned.text)")
                }

            default:
                // Skip everything else: tool_result user entries (handled as part of user above,
                // but those have content as array so processUserEntry bails), system messages,
                // file-history-snapshot, progress, queue-operation, last-prompt, etc.
                continue
            }
        }

        let jsonl = jsonlLines.isEmpty ? "" : jsonlLines.joined(separator: "\n") + "\n"
        let plainText = plainTextParts.joined(separator: "\n\n")

        return CleanResult(
            jsonl: jsonl,
            sessionId: newSessionId,
            userCount: userCount,
            assistantCount: assistantCount,
            plainText: plainText
        )
    }

    // MARK: - User entry processing

    private struct ProcessedEntry {
        var dict: [String: Any]
        let newUuid: String
        let text: String
    }

    private func processUserEntry(
        dict: [String: Any],
        entryIndex: Int,
        newSessionId: String,
        parentUuid: String?,
        displayMessages: [DisplayMessage],
        editedTexts: [String: String],
        deletedMessageIds: Set<String>,
        stripRuntimeNoise: Bool
    ) -> ProcessedEntry? {
        // Must have message with string content (text message, not tool_result)
        guard let msg = dict["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            return nil
        }

        // Skip compact summaries — they're not real conversation
        if dict["isCompactSummary"] as? Bool == true { return nil }
        if dict["isVisibleInTranscriptOnly"] as? Bool == true { return nil }

        // Check if this message is marked for deletion
        var displayId: String? = nil
        for dmsg in displayMessages {
            if case .userText(let utm) = dmsg {
                displayId = utm.id
                break
            }
        }

        if let did = displayId, deletedMessageIds.contains(did) {
            return nil
        }

        // Apply edit if present
        var finalContent = content
        if let did = displayId, let edited = editedTexts[did] {
            finalContent = edited
        }

        // Strip Claude Code's runtime-noise wrappers if enabled. See
        // cycle 45 findings — these wrappers carry no user intent and
        // muddy a cleaned dialogue extract.
        if stripRuntimeNoise {
            finalContent = Self.stripNoiseWrappers(from: finalContent)
        }

        // Skip empty messages
        if finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        // Rebuild the entry with new UUIDs, session, parent
        let newUuid = UUID().uuidString.lowercased()
        var cleaned = dict
        cleaned["uuid"] = newUuid
        cleaned["parentUuid"] = parentUuid as Any? ?? NSNull()
        cleaned["sessionId"] = newSessionId

        var cleanedMsg = msg
        cleanedMsg["content"] = finalContent
        cleaned["message"] = cleanedMsg

        return ProcessedEntry(dict: cleaned, newUuid: newUuid, text: finalContent)
    }

    // MARK: - Assistant entry processing

    private func processAssistantEntry(
        dict: [String: Any],
        entryIndex: Int,
        newSessionId: String,
        parentUuid: String?,
        displayMessages: [DisplayMessage],
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> ProcessedEntry? {
        // Skip API errors
        if dict["isApiErrorMessage"] as? Bool == true { return nil }

        guard var msg = dict["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else {
            return nil
        }

        // Build map: original blockIdx -> displayMessage
        var displayByBlockIdx: [Int: AssistantTextMessage] = [:]
        for dmsg in displayMessages {
            if case .assistantText(let atm) = dmsg {
                displayByBlockIdx[atm.blockIndex] = atm
            }
        }

        // Walk original content in order, keep only text blocks.
        // Drop deleted text blocks. Apply edits.
        var keptBlocks: [[String: Any]] = []
        var combinedText: [String] = []

        for (idx, block) in content.enumerated() {
            guard (block["type"] as? String) == "text" else { continue }

            let originalText = (block["text"] as? String) ?? ""
            var finalText = originalText

            if let dmsg = displayByBlockIdx[idx] {
                if deletedMessageIds.contains(dmsg.id) { continue }
                if let edited = editedTexts[dmsg.id] {
                    finalText = edited
                }
            }

            // Drop empty text blocks
            if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            var newBlock = block
            newBlock["text"] = finalText
            keptBlocks.append(newBlock)
            combinedText.append(finalText)
        }

        // If no text blocks survived, drop the entire assistant entry
        if keptBlocks.isEmpty { return nil }

        // Rebuild the entry
        let newUuid = UUID().uuidString.lowercased()
        var cleaned = dict
        cleaned["uuid"] = newUuid
        cleaned["parentUuid"] = parentUuid as Any? ?? NSNull()
        cleaned["sessionId"] = newSessionId

        msg["content"] = keptBlocks

        // If stop_reason was "tool_use", change it — there are no tools in this response now
        if (msg["stop_reason"] as? String) == "tool_use" {
            msg["stop_reason"] = "end_turn"
        }

        // The API's reported usage (input/output/cache tokens) was for the
        // ORIGINAL message with full context (tools, system, etc.). Those
        // numbers no longer describe this cleaned entry. Strip them so the
        // context badge and cost estimate don't show stale peaks.
        msg.removeValue(forKey: "usage")
        // Also strip response-level identifiers that were tied to the
        // original API call — they don't refer to anything anymore.
        msg.removeValue(forKey: "id")
        msg.removeValue(forKey: "stop_details")
        cleaned.removeValue(forKey: "requestId")

        cleaned["message"] = msg

        return ProcessedEntry(
            dict: cleaned,
            newUuid: newUuid,
            text: combinedText.joined(separator: "\n\n")
        )
    }

    // MARK: - JSON helpers

    private func parseJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func serializeJSON(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Runtime-noise wrapper stripping

    /// Tags Claude Code injects into user-text bodies that aren't part of
    /// the user's intent. Stripped from cleaned dialogue when
    /// `stripRuntimeNoise` is true.
    private static let noiseTags = [
        "system-reminder",
        "local-command-caveat",
        "command-stdout",
        "command-stderr"
    ]

    /// Remove `<tag>...</tag>` blocks for any well-known noise tag.
    /// Multiline-aware. Whitespace cleaned up at the join.
    static func stripNoiseWrappers(from text: String) -> String {
        var out = text
        for tag in noiseTags {
            // (?s) = dotall, so .* spans newlines.
            let pattern = "(?s)<\(tag)\\b[^>]*>.*?</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
        }
        // Collapse runs of blank lines that the strip can leave behind.
        if let collapse = try? NSRegularExpression(pattern: "\n{3,}", options: []) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = collapse.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "\n\n")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
