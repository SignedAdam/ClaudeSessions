import SwiftUI

struct ConversationContainerView: View {
    let conversation: Conversation
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeStore: ThemeStore

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                SessionHeaderView()
                ConversationToolbar()

                if appState.isJSONMode {
                    JSONEditorView(conversation: conversation)
                } else {
                    ConversationView(conversation: conversation)
                        // iMessage mode takes over the background too — authentic
                        // iOS Messages backdrop, not the active palette.
                        .background(conversationBackground)
                }
            }

            if let toast = appState.toastMessage {
                ToastView(message: toast)
                    .padding(.bottom, 50)
                    .animation(.spring(response: 0.3), value: appState.toastMessage)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $appState.showExportSheet) {
            ExportSheetView(
                conversation: conversation,
                title: appState.currentSessionTitle ?? "Conversation",
                isPresented: $appState.showExportSheet
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showContextSheet) {
            if let metrics = appState.contextMetrics {
                ContextDetailView(metrics: metrics, isPresented: $appState.showContextSheet)
                    .environmentObject(appState)
                    .environmentObject(themeStore)
            }
        }
    }

    /// iMessage mode draws on top of authentic iOS Messages background.
    /// Document mode keeps the app's ambient field + theme background.
    private var conversationBackground: Color {
        if themeStore.conversationStyle == .iMessage {
            return Theme.isLight
                ? Color(hex: 0xffffff)           // iOS light Messages background
                : Color(hex: 0x000000)           // iOS dark Messages background
        }
        return Color.clear
    }
}
