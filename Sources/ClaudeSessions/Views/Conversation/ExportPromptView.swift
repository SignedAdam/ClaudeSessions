import SwiftUI

struct ExportPromptView: View {
    let conversation: Conversation
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var selectedIds: Set<String> = []
    @State private var format: ExportFormat = .labeled
    @State private var copied = false

    enum ExportFormat: String, CaseIterable {
        case labeled = "Labeled"
        case bare = "Bare"
        case markdown = "Markdown"
    }

    private var exportableMessages: [(id: String, role: String, text: String)] {
        conversation.displayMessages.compactMap { msg in
            switch msg {
            case .userText(let m):
                if m.isCompactSummary { return nil }
                let text = appState.getDisplayText(messageId: m.id, originalText: m.text)
                return (m.id, "user", text)
            case .assistantText(let m):
                if m.isApiError { return nil }
                let text = appState.getDisplayText(messageId: m.id, originalText: m.text)
                return (m.id, "assistant", text)
            default:
                return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export as Prompt")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Format picker
            HStack(spacing: 12) {
                Text("Format:")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Picker("", selection: $format) {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                Button("Select All") {
                    selectedIds = Set(exportableMessages.map(\.id))
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.humanTint)

                Button("Deselect All") {
                    selectedIds = []
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Message list with checkboxes
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(exportableMessages, id: \.id) { msg in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { selectedIds.contains(msg.id) },
                                set: { isOn in
                                    if isOn { selectedIds.insert(msg.id) }
                                    else { selectedIds.remove(msg.id) }
                                }
                            ))
                            .toggleStyle(.checkbox)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg.role == "user" ? appState.displayName : "Claude")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(msg.role == "user" ? Theme.humanTint : Theme.accent)
                                Text(msg.text.prefix(200).description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text.opacity(0.8))
                                    .lineLimit(3)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(selectedIds.contains(msg.id) ? Theme.surface2 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Preview of formatted output (collapsed)
            if !selectedIds.isEmpty {
                DisclosureGroup("Preview (\(selectedIds.count) messages)") {
                    ScrollView {
                        Text(formattedOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text.opacity(0.8))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Theme.codeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            Divider()

            // Actions
            HStack {
                Text("\(selectedIds.count) messages selected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(formattedOutput, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selectedIds.isEmpty ? Theme.textSecondary.opacity(0.3) : Theme.accent)
                .clipShape(Capsule())
                .disabled(selectedIds.isEmpty)

                if copied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.toolTint)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 600, height: 550)
        .background(Theme.surface)
        .onAppear {
            // Default: select all
            selectedIds = Set(exportableMessages.map(\.id))
        }
    }

    private var formattedOutput: String {
        let selected = exportableMessages.filter { selectedIds.contains($0.id) }

        switch format {
        case .labeled:
            return selected.map { msg in
                let label = msg.role == "user" ? "[\(appState.displayName)]" : "[Claude]"
                return "\(label)\n\(msg.text)"
            }.joined(separator: "\n\n")

        case .bare:
            return selected.map(\.text).joined(separator: "\n\n---\n\n")

        case .markdown:
            return selected.map { msg in
                let header = msg.role == "user" ? "## \(appState.displayName)" : "## Claude"
                return "\(header)\n\n\(msg.text)"
            }.joined(separator: "\n\n---\n\n")
        }
    }
}
