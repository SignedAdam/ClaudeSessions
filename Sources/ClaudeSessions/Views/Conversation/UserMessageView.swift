import SwiftUI

struct UserMessageView: View {
    let message: UserTextMessage
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeStore: ThemeStore
    @State private var copied = false
    @State private var isHovering = false
    @State private var editText = ""

    private var isEditing: Bool { appState.editingMessageId == message.id }
    private var isDeleted: Bool { appState.deletedMessageIds.contains(message.id) }
    private var displayText: String { appState.getDisplayText(messageId: message.id, originalText: message.text) }

    var body: some View {
        if message.isCompactSummary {
            compactSummaryView
        } else if isDeleted {
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
                .fill(Theme.humanTint.opacity(0.35))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                // Content slot — same outer padding whether viewing or editing.
                // Only the INNER view swaps.
                if isEditing {
                    seamlessEditor
                } else {
                    Text(displayText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isEditing {
                    editControls
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.humanTint.opacity(isHovering ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isEditing ? Theme.accent.opacity(0.35) :
                    (isHovering ? Theme.humanTint.opacity(0.25) : Color.clear),
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
            Spacer(minLength: 60)

            // The bubble + its overlay of hover actions.
            // Actions overlay the bubble itself — no risk of slipping off.
            ZStack(alignment: .topTrailing) {
                Group {
                    if isEditing {
                        // Seamless editor — same bubble, same size, just editable
                        bubbleEditor(tail: .right, bg: Color(hex: 0x0a84ff), fg: .white)
                    } else {
                        Text(displayText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white)
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Color(hex: 0x0a84ff))
                            .clipShape(BubbleShape(tail: .right))
                    }
                }
                .frame(maxWidth: 520, alignment: .trailing)

                hoverActionsOverlay
                    .padding(6)
            }

            if isEditing {
                // Controls below bubble, right-aligned for consistency
            }
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottomTrailing) {
            if isEditing {
                editControls
                    .padding(.trailing, 70)
                    .padding(.bottom, -22)
            }
        }
        .padding(.bottom, isEditing ? 20 : 0)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .contextMenu { messageContextMenu }
    }

    // MARK: - Seamless editor (document style — inline Text replacement)

    private var seamlessEditor: some View {
        // TextEditor styled to match the Text view it replaces: same font,
        // same color, transparent background, minimal padding compensation.
        TextEditor(text: $editText)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            // TextEditor has ~5pt internal horizontal padding by default.
            // Negative padding compensates so it aligns with Text's edges.
            .padding(.horizontal, -5)
            .frame(minHeight: 22, maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// iMessage bubble variant of the seamless editor — keeps the bubble
    /// shape/color while the inside becomes editable.
    private func bubbleEditor(tail: BubbleShape.Side, bg: Color, fg: Color) -> some View {
        TextEditor(text: $editText)
            .font(.system(size: 14))
            .foregroundStyle(fg)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.horizontal, 13 - 5)    // account for TextEditor's own padding
            .padding(.vertical, 8)
            .frame(minHeight: 30, maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
            .background(bg)
            .clipShape(BubbleShape(tail: tail))
    }

    // MARK: - Edit controls (simple text, no chrome)

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

    // MARK: - Hover actions overlay

    /// Floats in the top-right corner of the message. Hidden while editing
    /// so nothing interferes with the editor.
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

    // MARK: - Deleted / compact

    private var deletedView: some View {
        HStack {
            Rectangle().fill(Theme.errorTint.opacity(0.3)).frame(width: 3)
            Text(displayText).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).strikethrough().lineLimit(1)
            Spacer()
            Button("Undo") { appState.undeleteMessage(messageId: message.id) }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent).buttonStyle(.plain)
        }
        .padding(.vertical, 4).padding(.trailing, 14).opacity(0.6)
    }

    private var compactSummaryView: some View {
        DisclosureGroup {
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .padding(10)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 8))
                Text("context summary").font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
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
        NSPasteboard.general.setString("[\(appState.displayName) \u{2014} \(ts)]\n\(displayText)", forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Bubble shape

struct BubbleShape: Shape {
    enum Side { case left, right }
    let tail: Side
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let tailR: CGFloat = 4
        var path = Path()

        if tail == .right {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tailR))
            path.addArc(center: CGPoint(x: rect.maxX - tailR, y: rect.maxY - tailR), radius: tailR,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + tailR, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + tailR, y: rect.maxY - tailR), radius: tailR,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        return path
    }
}
