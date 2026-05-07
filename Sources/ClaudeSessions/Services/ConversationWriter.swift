import Foundation

struct ConversationWriter {
    /// Write a modified conversation back to its JSONL file.
    /// Preserves unmodified entries byte-for-byte via rawJSON.
    func write(conversation: Conversation, editedTexts: [String: String]) throws {
        let filePath = conversation.filePath
        let url = URL(fileURLWithPath: filePath)

        var lines: [String] = []

        for indexed in conversation.rawEntries {
            if conversation.deletedIndices.contains(indexed.index) {
                continue
            }

            // Check if any display message at this entry index was edited
            let editedLine = applyEdits(indexed: indexed, editedTexts: editedTexts, conversation: conversation)

            if let edited = editedLine {
                lines.append(edited)
            } else {
                // Write the original raw JSON verbatim
                lines.append(indexed.rawJSON)
            }
        }

        let content = lines.joined(separator: "\n") + "\n"

        // Atomic write: write to temp file, then rename
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)

        // Replace original
        let fm = FileManager.default
        if fm.fileExists(atPath: filePath) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: tempURL, to: url)
    }

    private func applyEdits(indexed: IndexedEntry, editedTexts: [String: String], conversation: Conversation) -> String? {
        // Find display messages that reference this entry index
        for msg in conversation.displayMessages {
            switch msg {
            case .userText(let m):
                if m.entryIndex == indexed.index, let newText = editedTexts[m.id] {
                    return rebuildUserTextEntry(rawJSON: indexed.rawJSON, newText: newText)
                }
            case .assistantText(let m):
                if m.entryIndex == indexed.index, let newText = editedTexts[m.id] {
                    return rebuildAssistantTextEntry(rawJSON: indexed.rawJSON, blockIndex: m.blockIndex, newText: newText)
                }
            default:
                break
            }
        }
        return nil
    }

    private func rebuildUserTextEntry(rawJSON: String, newText: String) -> String? {
        guard var dict = parseJSON(rawJSON) else { return nil }
        guard var message = dict["message"] as? [String: Any] else { return nil }

        // User text messages have content as a string
        message["content"] = newText
        dict["message"] = message

        return serializeJSON(dict)
    }

    private func rebuildAssistantTextEntry(rawJSON: String, blockIndex: Int, newText: String) -> String? {
        guard var dict = parseJSON(rawJSON) else { return nil }
        guard var message = dict["message"] as? [String: Any] else { return nil }
        guard var content = message["content"] as? [[String: Any]] else { return nil }

        guard blockIndex < content.count else { return nil }
        content[blockIndex]["text"] = newText
        message["content"] = content
        dict["message"] = message

        return serializeJSON(dict)
    }

    private func parseJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func serializeJSON(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
