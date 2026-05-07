import SwiftUI

/// Compose box that sits at the bottom of `ConversationContainerView` when
/// a conversation is open and we're not in JSON mode. Multi-line text
/// editor + Send button. ⌘↩ submits.
///
/// While a previous send is in-flight (`appState.isComposerSending`), the
/// editor and button are disabled and a spinner replaces the Send icon.
///
/// Real submit goes via `appState.submitComposer()` which currently is a
/// stub — the subprocess plumbing lands in P2.T03 (`ClaudeRunner`).
struct ComposerView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(alignment: .bottom, spacing: 8) {
                editor
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder shown only when text is empty and editor isn't
            // currently being edited. A real TextEditor doesn't have a
            // built-in placeholder, so we overlay one.
            if appState.composerText.isEmpty {
                Text(placeholderText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $appState.composerText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .disabled(appState.isComposerSending)
                .frame(minHeight: 32, maxHeight: 140)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .onSubmit { appState.submitComposer() }
        }
        .background(Theme.surface2.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isFocused ? Theme.accent.opacity(0.45) : Theme.border.opacity(0.4),
                    lineWidth: 1
                )
        )
        // ⌘↩ submit. Bound to a hidden Button below so it works regardless
        // of focus, as long as the conversation pane is in the responder chain.
        .background(
            Button {
                appState.submitComposer()
            } label: { EmptyView() }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    private var sendButton: some View {
        Button {
            appState.submitComposer()
        } label: {
            ZStack {
                if appState.isComposerSending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSubmit ? Theme.accent : Theme.textTertiary)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .help(canSubmit ? "Send (⌘↩)" : "Type something to send")
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        !appState.isComposerSending
            && !appState.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholderText: String {
        if appState.isComposerSending {
            return "sending…"
        }
        return "Reply to Claude — runs `claude -p --resume` under the hood (⌘↩ to send)"
    }
}
