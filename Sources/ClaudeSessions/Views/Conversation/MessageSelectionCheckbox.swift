import SwiftUI

/// Leading-edge checkbox shown next to user/assistant messages while in
/// select mode. Click toggles membership in `appState.selectedMessageIds`.
/// Mirrors the iconography of macOS's native checkmark.circle pattern.
struct MessageSelectionCheckbox: View {
    let messageId: String
    @EnvironmentObject var appState: AppState

    private var isOn: Bool { appState.selectedMessageIds.contains(messageId) }

    var body: some View {
        Button {
            appState.toggleSelection(messageId: messageId)
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
                .contentShape(Rectangle())
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Deselect this message" : "Select this message")
    }
}
