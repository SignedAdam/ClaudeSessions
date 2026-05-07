import AppKit

/// Clipboard formatters for conversation content.
enum ClipboardService {

    /// Full transcript — every visible message, including tools and system events.
    /// Applies edits and respects deletions.
    static func formatFullTranscript(
        displayMessages: [DisplayMessage],
        displayName: String,
        editedTexts: [String: String],
        deletedMessageIds: Set<String>
    ) -> String {
        displayMessages.compactMap { msg -> String? in
            if deletedMessageIds.contains(msg.id) { return nil }

            switch msg {
            case .userText(let m):
                if m.isCompactSummary { return nil }
                let text = editedTexts[m.id] ?? m.text
                let ts = m.timestamp.map { DateFormatting.timeString($0) } ?? ""
                return "[\(displayName) \u{2014} \(ts)]\n\(text)"
            case .assistantText(let m):
                if m.isApiError { return nil }
                let text = editedTexts[m.id] ?? m.text
                let ts = m.timestamp.map { DateFormatting.timeString($0) } ?? ""
                return "[Claude \u{2014} \(ts)]\n\(text)"
            case .toolInteraction(let interaction):
                let ts = interaction.toolCall.timestamp.map { DateFormatting.timeString($0) } ?? ""
                var out = "[Tool: \(interaction.toolCall.toolName) \u{2014} \(ts)]\n\(interaction.toolCall.summary)"
                if let r = interaction.toolResult {
                    let resultLabel = r.isError ? "Error" : "Result"
                    out += "\n\n[\(resultLabel) \u{2014} \(ts)]\n\(r.resultText)"
                }
                return out
            case .toolCall(let m):
                let ts = m.timestamp.map { DateFormatting.timeString($0) } ?? ""
                return "[Tool: \(m.toolName) \u{2014} \(ts)]\n\(m.summary)"
            case .toolResult(let m):
                let ts = m.timestamp.map { DateFormatting.timeString($0) } ?? ""
                return "[\(m.isError ? "Error" : "Result") \u{2014} \(ts)]\n\(m.resultText)"
            case .systemMessage(let m):
                let ts = m.timestamp.map { DateFormatting.timeString($0) } ?? ""
                return "[System · \(m.subtype) \u{2014} \(ts)]\n\(m.content)"
            case .compactBoundary:
                return "[Conversation compacted]"
            }
        }.joined(separator: "\n\n")
    }

    /// Multi-select copy — same formatter, used for selected message subset.
    static func copyMessages(_ messages: [DisplayMessage], displayName: String, editedTexts: [String: String]) {
        let text = formatFullTranscript(
            displayMessages: messages,
            displayName: displayName,
            editedTexts: editedTexts,
            deletedMessageIds: []
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
