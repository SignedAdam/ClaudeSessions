import SwiftUI

struct ToolResultView: View {
    let result: ToolResultMessage
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
                    Circle()
                        .fill(result.isError ? Theme.errorTint : Theme.successTint)
                        .frame(width: 5, height: 5)
                        .opacity(0.6)
                        .frame(width: 16)
                    Text(result.resultText.prefix(100).description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(result.resultText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.7))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 250)
                .background(Theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }
}
