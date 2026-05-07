import SwiftUI

struct SystemMessageView: View {
    let message: SystemDisplayMessage

    var body: some View {
        // System messages: barely visible, a whisper in the timeline
        HStack(spacing: 6) {
            Text("\u{2014}")
                .foregroundStyle(Theme.textFaint)
            Text(displayContent)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private var displayContent: String {
        switch message.subtype {
        case "turn_duration":
            if let ms = message.durationMs { return "\(String(format: "%.1f", Double(ms) / 1000))s" }
            return message.content
        case "local_command": return message.content
        case "bridge_status": return "remote session"
        default: return message.content
        }
    }
}

struct CompactBoundaryView: View {
    let message: CompactBoundaryMessage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Theme.textFaint).frame(width: 2, height: 2)
            }
            Text("compacted")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
            if let tokens = message.preTokens {
                Text("\(tokens / 1000)K")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Theme.textFaint).frame(width: 2, height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
