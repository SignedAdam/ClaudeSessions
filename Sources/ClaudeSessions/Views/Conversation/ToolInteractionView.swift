import SwiftUI

struct ToolInteractionView: View {
    let interaction: ToolInteraction
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // One-line summary — the tool call as a single readable line
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 16)

                    // Tool icon
                    Image(systemName: toolIcon(interaction.toolCall.toolName))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.toolTint.opacity(0.6))
                        .frame(width: 16)

                    // Tool name
                    Text(interaction.toolCall.toolName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.toolTint.opacity(0.7))

                    // Summary
                    Text(" \u{203A} ")
                        .foregroundStyle(Theme.textFaint)
                    Text(interaction.toolCall.summary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Status dot
                    if let result = interaction.toolResult {
                        Circle()
                            .fill(result.isError ? Theme.errorTint : Theme.successTint)
                            .frame(width: 5, height: 5)
                            .opacity(0.6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.surface.opacity(isExpanded ? 1 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contextMenu {
            Button("Copy Input") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(interaction.toolCall.summary, forType: .string)
            }
            if let result = interaction.toolResult {
                Button("Copy Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.resultText, forType: .string)
                }
            }
            Button("Copy as JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(formatInput(interaction.toolCall.input), forType: .string)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Input
            ScrollView(.horizontal, showsIndicators: false) {
                Text(formatInput(interaction.toolCall.input))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.7))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 180)
            .background(Theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Result
            if let result = interaction.toolResult {
                HStack(spacing: 4) {
                    Circle().fill(result.isError ? Theme.errorTint : Theme.successTint).frame(width: 4, height: 4)
                    Text(result.isError ? "error" : "output")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(result.isError ? Theme.errorTint.opacity(0.6) : Theme.textTertiary)
                }

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(result.resultText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(result.isError ? Theme.errorTint.opacity(0.7) : Theme.text.opacity(0.7))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 250)
                .background(Theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func formatInput(_ input: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) { return str }
        return String(describing: input)
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Bash": return "terminal.fill"
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil.line"
        case "Grep": return "magnifyingglass"
        case "Glob": return "doc.text.magnifyingglass"
        case "Agent": return "person.2"
        case "WebSearch": return "globe"
        case "TaskCreate", "TaskUpdate": return "checklist"
        default: return "wrench"
        }
    }
}
