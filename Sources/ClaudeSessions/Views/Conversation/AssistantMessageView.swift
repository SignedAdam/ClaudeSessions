import SwiftUI

struct AssistantMessageView: View {
    let message: AssistantTextMessage
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeStore: ThemeStore
    @State private var copied = false
    @State private var isHovering = false
    @State private var editText = ""

    private var isEditing: Bool { appState.editingMessageId == message.id }
    private var isDeleted: Bool { appState.deletedMessageIds.contains(message.id) }
    private var displayText: String { appState.getDisplayText(messageId: message.id, originalText: message.text) }

    var body: some View {
        if appState.isSelectMode && !isDeleted {
            HStack(alignment: .top, spacing: 8) {
                MessageSelectionCheckbox(messageId: message.id)
                    .padding(.top, 6)
                messageContent
            }
        } else {
            messageContent
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if isDeleted {
            deletedView
        } else {
            switch themeStore.conversationStyle {
            case .document:
                documentView
            case .iMessage:
                iMessageView
            }
        }
    }

    // MARK: - Document style

    private var documentView: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Theme.accent.opacity(0.2))
                .frame(width: 2)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if isEditing {
                    seamlessMarkdownEditor
                } else if message.isApiError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                        Text(displayText).font(.system(size: 13))
                    }
                    .foregroundStyle(Theme.errorTint)
                    .padding(.vertical, 4)
                } else {
                    MarkdownRenderer(text: displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isEditing {
                    editControls
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 2)
        .background(isHovering ? Theme.hoverGlow : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isEditing ? Theme.accent.opacity(0.35) :
                    (isHovering ? Theme.accent.opacity(0.15) : Color.clear),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topTrailing) {
            hoverActionsOverlay
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .contextMenu { messageContextMenu }
    }

    // MARK: - iMessage style

    private var iMessageView: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isEditing {
                        bubbleEditor(bg: iMessageContactBg, fg: iMessageContactText)
                    } else if message.isApiError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                            Text(displayText).font(.system(size: 13))
                        }
                        .foregroundStyle(Color(hex: 0xff453a))
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(Color(hex: 0xffe5e3))
                        .clipShape(BubbleShape(tail: .left))
                    } else {
                        MarkdownRenderer(text: displayText)
                            .foregroundStyle(iMessageContactText)
                            .tint(Color(hex: 0x0a84ff))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(iMessageContactBg)
                            .clipShape(BubbleShape(tail: .left))
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)

                hoverActionsOverlay
                    .padding(6)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottomLeading) {
            if isEditing {
                editControls
                    .padding(.leading, 70)
                    .padding(.bottom, -22)
            }
        }
        .padding(.bottom, isEditing ? 20 : 0)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .contextMenu { messageContextMenu }
    }

    // iMessage contact colors — hard-coded, palette-independent.
    private var iMessageContactBg: Color {
        Theme.isLight ? Color(hex: 0xe9e9eb) : Color(hex: 0x2c2c2e)
    }
    private var iMessageContactText: Color {
        Theme.isLight ? Color.black : Color.white
    }

    // MARK: - Seamless editor

    /// Document-style editor — matches MarkdownRenderer's padding/typography.
    /// Shows RAW markdown source since that's what the user is editing.
    private var seamlessMarkdownEditor: some View {
        TextEditor(text: $editText)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.horizontal, -5)
            .frame(minHeight: 30, maxHeight: 600)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bubbleEditor(bg: Color, fg: Color) -> some View {
        TextEditor(text: $editText)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(fg)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.horizontal, 13 - 5)
            .padding(.vertical, 9)
            .frame(minHeight: 30, maxHeight: 600)
            .fixedSize(horizontal: false, vertical: true)
            .background(bg)
            .clipShape(BubbleShape(tail: .left))
    }

    // MARK: - Edit controls

    private var editControls: some View {
        HStack(spacing: 16) {
            Spacer()
            Button("Cancel") { appState.cancelEdit(messageId: message.id, originalText: message.text) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            Button("Save") {
                appState.editedTexts[message.id] = editText
                appState.commitEdit(messageId: message.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - Hover actions

    private var hoverActionsOverlay: some View {
        HStack(spacing: 4) {
            hoverButton("pencil") {
                editText = displayText
                appState.startEditing(messageId: message.id, currentText: message.text)
            }
            hoverButton(copied ? "checkmark" : "doc.on.doc") { copyMessage() }
            continueFromHereButton
        }
        .padding(8)
        .opacity((isHovering && !isEditing) ? 1 : 0)
        .allowsHitTesting(isHovering && !isEditing)
    }

    private var continueFromHereButton: some View {
        Button {
            appState.continueFromMessage(id: message.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold))
                Text("continue here").font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Fork a new Claude Code session containing this conversation up to and including this message.")
    }

    // MARK: - Deleted

    private var deletedView: some View {
        HStack {
            Rectangle().fill(Theme.errorTint.opacity(0.3)).frame(width: 2)
            Text(displayText).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).strikethrough().lineLimit(1)
                .padding(.leading, 14)
            Spacer()
            Button("Undo") { appState.undeleteMessage(messageId: message.id) }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent).buttonStyle(.plain)
        }
        .padding(.vertical, 4).padding(.trailing, 14).opacity(0.5)
    }

    private func hoverButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        Button("Copy Message") { copyMessage() }
        Button("Copy Raw Markdown") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(displayText, forType: .string)
        }
        Button("Edit Message") {
            editText = displayText
            appState.startEditing(messageId: message.id, currentText: message.text)
        }
        Divider()
        Button("Delete Message", role: .destructive) { appState.deleteMessage(messageId: message.id) }
    }

    private func copyMessage() {
        let ts = message.timestamp.map { DateFormatting.timeString($0) } ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[Claude \u{2014} \(ts)]\n\(displayText)", forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Model pill (used in GroupHeaderView)

struct ModelPill: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
    }
}
