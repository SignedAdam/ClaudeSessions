import Foundation

/// Writes the current conversation as a BRAND-NEW session file, applying
/// user edits and deletions, but preserving *all* entries (tool calls,
/// tool results, system messages, file-history-snapshots, etc.).
///
/// Different from CleanConversationService — that one strips non-dialogue
/// entries. This one is a full fork: same content, new session identity.
///
/// Purpose: when the user edits a message, we never overwrite the original.
/// Instead we fork to a new session file, and the original is marked
/// archived in sessions-index.json (see SessionCreator.updateSessionTitle).
struct SessionForker {

    struct ForkResult {
        let jsonl: String
        let sessionId: String
        let messageCount: Int  // user + assistant text count for the index
    }

    func fork(
        conversation: Conversation,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> ForkResult {
        let newSessionId = UUID().uuidString.lowercased()
        var lines: [String] = []
        // Important: chain ONLY dialogue entries to each other. Metadata
        // entries (custom-title, summary, file-history-snapshot,
        // attachment, agent-setting, last-prompt, permission-mode, etc.)
        // are out-of-band records that should NOT participate in the
        // parentUuid chain. If they're inserted into the chain, Claude
        // Code's `--resume` walks back from the tip, hits a metadata
        // entry as a parent, can't resolve it as dialogue, and treats
        // the next dialogue entry as a root — collapsing the visible
        // history to a single message.
        let dialogueTypes: Set<String> = ["user", "assistant", "system"]
        var lastDialogueUuid: String? = nil
        var userCount = 0
        var assistantCount = 0

        // Map: source entryIndex → [display messages]
        var displayByIndex: [Int: [DisplayMessage]] = [:]
        for m in conversation.displayMessages {
            displayByIndex[m.entryIndex, default: []].append(m)
        }

        for indexed in conversation.rawEntries {
            // Check whole-entry deletion via displayMessage id
            let displays = displayByIndex[indexed.index] ?? []
            let wholeEntryDeleted = isEntryWhollyDeleted(displays: displays, deletedIds: deletedMessageIds)
            if wholeEntryDeleted { continue }

            guard var dict = parseJSON(indexed.rawJSON) else {
                // Malformed — include verbatim so we don't lose data
                lines.append(indexed.rawJSON)
                continue
            }

            // Apply edits for this entry type
            let entryType = dict["type"] as? String ?? ""
            switch entryType {
            case "user":
                applyUserEdits(&dict, entryIndex: indexed.index, editedTexts: editedTexts, displays: displays)
            case "assistant":
                applyAssistantEdits(&dict, entryIndex: indexed.index, editedTexts: editedTexts,
                                    deletedIds: deletedMessageIds, displays: displays)
            default:
                break
            }

            // Re-identify: new uuid, new session id.
            let newUuid = UUID().uuidString.lowercased()
            dict["uuid"] = newUuid
            dict["sessionId"] = newSessionId

            if dialogueTypes.contains(entryType) {
                // Chain dialogue entries to the previous dialogue entry.
                dict["parentUuid"] = lastDialogueUuid.map { $0 as Any } ?? NSNull()
                if let json = serializeJSON(dict) {
                    lines.append(json)
                    lastDialogueUuid = newUuid

                    if entryType == "user",
                       let msg = dict["message"] as? [String: Any],
                       msg["content"] is String,
                       dict["isCompactSummary"] as? Bool != true {
                        userCount += 1
                    }
                    if entryType == "assistant" {
                        assistantCount += 1
                    }
                }
            } else {
                // Metadata entry: clear parentUuid (original referent no
                // longer exists after rewriting uuids) but keep the entry
                // so Claude Code still has the title/summary/snapshot data.
                dict["parentUuid"] = NSNull()
                if let json = serializeJSON(dict) {
                    lines.append(json)
                }
            }
        }

        let jsonl = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        return ForkResult(jsonl: jsonl, sessionId: newSessionId, messageCount: userCount + assistantCount)
    }

    /// Fork up to and including a specific display-message id. Everything
    /// after that message in the conversation is dropped. Tool calls and
    /// other side content that occur *before* the cutoff are preserved.
    ///
    /// Used by "Continue from here" — the user wants a new session whose
    /// state is "what the conversation was up to this point", which they
    /// can then resume in Claude Code without overwriting the original.
    func forkUpToMessage(
        conversation: Conversation,
        cutoffMessageId: String
    ) -> ForkResult? {
        guard let cutoff = conversation.displayMessages.first(where: { $0.id == cutoffMessageId }) else {
            return nil
        }
        let cutoffEntryIdx = cutoff.entryIndex
        let truncatedRaw = conversation.rawEntries.filter { $0.index <= cutoffEntryIdx }
        let truncatedDisplay = conversation.displayMessages.filter { $0.entryIndex <= cutoffEntryIdx }
        let truncated = Conversation(
            sessionId: conversation.sessionId,
            filePath: conversation.filePath,
            displayMessages: truncatedDisplay,
            rawEntries: truncatedRaw,
            stats: conversation.stats
        )
        return fork(conversation: truncated, editedTexts: [:], deletedMessageIds: [])
    }

    // MARK: - Edit application

    private func isEntryWhollyDeleted(displays: [DisplayMessage], deletedIds: Set<String>) -> Bool {
        guard !displays.isEmpty else { return false }
        // If every display message at this entry index is deleted, drop the whole entry.
        // (Catches user text deletions and single-text-block assistants.)
        return displays.allSatisfy { deletedIds.contains($0.id) }
    }

    private func applyUserEdits(
        _ dict: inout [String: Any],
        entryIndex: Int,
        editedTexts: [String: String],
        displays: [DisplayMessage]
    ) {
        guard var msg = dict["message"] as? [String: Any],
              msg["content"] is String else { return }

        // Find the userText display message and apply its edit if present
        for d in displays {
            if case .userText(let utm) = d {
                if let edited = editedTexts[utm.id] {
                    msg["content"] = edited
                    dict["message"] = msg
                }
                break
            }
        }
    }

    private func applyAssistantEdits(
        _ dict: inout [String: Any],
        entryIndex: Int,
        editedTexts: [String: String],
        deletedIds: Set<String>,
        displays: [DisplayMessage]
    ) {
        guard var msg = dict["message"] as? [String: Any],
              var content = msg["content"] as? [[String: Any]] else { return }

        // Build map of blockIndex → edit / delete
        var editByBlockIdx: [Int: String] = [:]
        var deletedBlockIdx: Set<Int> = []
        for d in displays {
            if case .assistantText(let atm) = d {
                if deletedIds.contains(atm.id) { deletedBlockIdx.insert(atm.blockIndex) }
                if let edit = editedTexts[atm.id] {
                    editByBlockIdx[atm.blockIndex] = edit
                }
            }
        }

        // Walk blocks, apply edits and drop deleted text blocks
        var newContent: [[String: Any]] = []
        for (idx, block) in content.enumerated() {
            if (block["type"] as? String) == "text" {
                if deletedBlockIdx.contains(idx) { continue }
                if let edited = editByBlockIdx[idx] {
                    var newBlock = block
                    newBlock["text"] = edited
                    newContent.append(newBlock)
                } else {
                    newContent.append(block)
                }
            } else {
                // Keep tool_use and other block types unchanged
                newContent.append(block)
            }
        }

        content = newContent
        msg["content"] = content
        dict["message"] = msg
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
}
