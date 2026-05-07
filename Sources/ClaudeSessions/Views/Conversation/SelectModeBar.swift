import SwiftUI

/// Slim header strip shown above ConversationView when select mode is
/// active. Displays the selection count and the available actions —
/// Select All (visible), Copy, Cancel.
///
/// Cancel exits select mode and clears the selection. Copy formats
/// the selected messages and writes them to the clipboard via
/// `appState.copySelection()` (which fires its own toast on success).
struct SelectModeBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Theme.accent)

            Text("\(appState.selectedMessageIds.count) selected")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)

            Spacer()

            Button("Select all visible") {
                appState.selectAllVisible()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)

            Button {
                appState.copySelection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)
            .disabled(appState.selectedMessageIds.isEmpty)

            Button("Cancel") {
                appState.exitSelectMode()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.accent.opacity(0.4)).frame(height: 1)
        }
    }
}
