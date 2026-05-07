import SwiftUI

struct MessageView: View {
    let message: DisplayMessage
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch message {
        case .userText(let msg):
            UserMessageView(message: msg)
        case .assistantText(let msg):
            AssistantMessageView(message: msg)
        case .toolInteraction(let interaction):
            ToolInteractionView(interaction: interaction)
        case .toolCall(let msg):
            ToolCallView(call: msg)
        case .toolResult(let msg):
            ToolResultView(result: msg)
        case .systemMessage(let msg):
            SystemMessageView(message: msg)
        case .compactBoundary(let msg):
            CompactBoundaryView(message: msg)
        }
    }
}
