import SwiftUI

struct ConversationView: View {
    let conversation: Conversation
    @EnvironmentObject var appState: AppState

    private let topAnchorId = "conversation-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchorId)

                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        render(item)
                    }

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onChange(of: conversation.sessionId) { _, _ in
                proxy.scrollTo(topAnchorId, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func render(_ item: Item) -> some View {
        switch item {
        case .groupHeader(let data):
            GroupHeaderView(
                role: data.role,
                displayName: data.displayName,
                model: data.model,
                timestamp: data.timestamp,
                timestampRaw: data.timestampRaw
            )
        case .message(let msg):
            MessageView(message: msg)
                .id(msg.id)
        }
    }

    // MARK: - Items

    private enum Item {
        case groupHeader(GroupHeaderData)
        case message(DisplayMessage)
    }

    private struct GroupHeaderData {
        let role: GroupHeaderView.Role
        let displayName: String
        let model: String?
        let timestamp: Date?
        let timestampRaw: String?
    }

    // MARK: - Filtering

    private var filteredMessages: [DisplayMessage] {
        switch (appState.isJSONMode, appState.isReadingMode) {
        case (true, _):
            return []
        case (_, true):
            return conversation.displayMessages.filter {
                switch $0 {
                case .userText(let m): return !m.isCompactSummary
                case .assistantText(let m): return !m.isApiError
                default: return false
                }
            }
        default:
            return conversation.displayMessages.filter {
                $0.isVisible(
                    showUser: appState.showUserMessages,
                    showAssistant: appState.showAssistantMessages,
                    showTool: appState.showToolMessages,
                    showSystem: appState.showSystemMessages
                )
            }
        }
    }

    // MARK: - Grouping

    /// Walk filtered messages. Emit a GroupHeader when the role changes or
    /// a significant time gap (>90s) opens up. Then emit the message itself.
    private var items: [Item] {
        let msgs = filteredMessages
        guard !msgs.isEmpty else { return [] }

        var result: [Item] = []
        var lastRole: GroupHeaderView.Role? = nil
        var lastTs: Date? = nil
        let gap: TimeInterval = 90

        for msg in msgs {
            let role = roleOf(msg)
            let ts = msg.timestamp

            let startsNewGroup: Bool = {
                if lastRole != role { return true }
                if let last = lastTs, let now = ts, now.timeIntervalSince(last) > gap { return true }
                return result.isEmpty
            }()

            if startsNewGroup {
                result.append(.groupHeader(GroupHeaderData(
                    role: role,
                    displayName: displayNameFor(role: role, msg: msg),
                    model: modelFor(msg: msg),
                    timestamp: ts,
                    timestampRaw: timestampRawFor(msg: msg)
                )))
            }

            result.append(.message(msg))
            lastRole = role
            lastTs = ts ?? lastTs
        }

        return result
    }

    private func roleOf(_ msg: DisplayMessage) -> GroupHeaderView.Role {
        switch msg {
        case .userText: return .human
        case .assistantText: return .assistant
        case .toolInteraction, .toolCall, .toolResult: return .tool
        case .systemMessage, .compactBoundary: return .system
        }
    }

    private func displayNameFor(role: GroupHeaderView.Role, msg: DisplayMessage) -> String {
        switch role {
        case .human:     return appState.displayName
        case .assistant: return "claude"
        case .tool:      return "tool"
        case .system:    return "system"
        }
    }

    private func modelFor(msg: DisplayMessage) -> String? {
        if case .assistantText(let m) = msg, let model = m.model {
            return model.replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: "-", with: " ")
        }
        return nil
    }

    private func timestampRawFor(msg: DisplayMessage) -> String? {
        switch msg {
        case .userText(let m): return m.timestampRaw
        case .assistantText(let m): return m.timestampRaw
        default: return nil
        }
    }
}
