import SwiftUI

struct JSONEditorView: View {
    let conversation: Conversation
    @State private var showMessagesOnly = false

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Toggle(isOn: $showMessagesOnly) {
                    Text("Messages only")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Text("\(displayedEntries.count) entries")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Theme.surface.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border.opacity(0.3)).frame(height: 1)
            }

            // JSON lines
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayedEntries.enumerated()), id: \.offset) { idx, entry in
                        HStack(alignment: .top, spacing: 0) {
                            // Line number
                            Text("\(entry.index + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary.opacity(0.3))
                                .frame(width: 40, alignment: .trailing)
                                .padding(.trailing, 8)

                            // Type indicator
                            Circle()
                                .fill(colorForType(entry.entry.type))
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                                .padding(.trailing, 6)

                            // JSON content
                            Text(entry.rawJSON)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.text.opacity(0.85))
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 3)
                        .background(idx % 2 == 0 ? Color.clear : Theme.surface.opacity(0.15))
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Theme.background)
        }
    }

    private var displayedEntries: [IndexedEntry] {
        if showMessagesOnly {
            return conversation.rawEntries.filter {
                switch $0.entry.type {
                case .user, .assistant, .system: return true
                default: return false
                }
            }
        }
        return conversation.rawEntries
    }

    private func colorForType(_ type: EntryType) -> Color {
        switch type {
        case .user: return Theme.humanTint
        case .assistant: return Theme.accent
        case .system: return Theme.warnTint
        default: return Theme.textSecondary.opacity(0.3)
        }
    }
}
