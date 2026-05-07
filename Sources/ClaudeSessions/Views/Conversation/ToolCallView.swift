import SwiftUI

struct ToolCallView: View {
    let call: ToolCallMessage
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 16)
                    Image(systemName: "wrench")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.toolTint.opacity(0.6))
                        .frame(width: 16)
                    Text(call.toolName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.toolTint.opacity(0.7))
                    Text(" \u{203A} ").foregroundStyle(Theme.textFaint)
                    Text(call.summary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("pending")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.warnTint.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(formatInput(call.input))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.7))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(Theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }

    private func formatInput(_ input: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) { return str }
        return String(describing: input)
    }
}
