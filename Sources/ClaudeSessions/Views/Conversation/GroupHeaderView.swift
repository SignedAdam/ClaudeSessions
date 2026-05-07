import SwiftUI

/// Section header shown between runs of same-speaker messages.
///
/// This separates message groups visually — like a section divider in a
/// transcript. Instead of repeating "claude · opus 4-6 · 03:14" inside
/// every message, we show it ONCE above the first message in a group.
///
/// Three render variants based on conversationStyle:
///   .document  → left-aligned name + model pill + precise time
///   .iMessage  → centered "Today 3:14 PM" style timestamp; role stamp above bubble
struct GroupHeaderView: View {
    enum Role { case human, assistant, tool, system }

    let role: Role
    let displayName: String      // "adam", "claude", "tool", "system"
    let model: String?           // e.g. "opus 4-6" — assistant only
    let timestamp: Date?
    let timestampRaw: String?    // for precise formatting

    @EnvironmentObject var themeStore: ThemeStore

    var body: some View {
        switch themeStore.conversationStyle {
        case .document:
            documentHeader
        case .iMessage:
            iMessageHeader
        }
    }

    // MARK: - Document

    private var documentHeader: some View {
        HStack(spacing: 8) {
            Text(displayName.lowercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(roleColor)

            if let model = model {
                Text(model)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(roleColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(roleColor.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(roleColor.opacity(0.3), lineWidth: 1)
                    )
            }

            if let t = timeString {
                Text(t)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            Rectangle()
                .fill(Theme.border.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - iMessage

    private var iMessageHeader: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text(iMessageTimeText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x8e8e93))       // iOS system gray
                if role == .assistant, let m = model {
                    Text("Claude · \(m)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0x8e8e93))
                }
            }
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Helpers

    private var roleColor: Color {
        switch role {
        case .human:     return Theme.humanTint
        case .assistant: return Theme.accent
        case .tool:      return Theme.toolTint
        case .system:    return Theme.warnTint
        }
    }

    private var timeString: String? {
        timestamp.map { DateFormatting.preciseTimeString($0, sourceISO: timestampRaw) }
    }

    private var iMessageTimeText: String {
        guard let d = timestamp else { return "" }
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) {
            f.dateFormat = "'Today' h:mm a"
        } else if cal.isDateInYesterday(d) {
            f.dateFormat = "'Yesterday' h:mm a"
        } else if cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) {
            f.dateFormat = "EEEE h:mm a"
        } else {
            f.dateFormat = "MMM d, h:mm a"
        }
        return f.string(from: d)
    }
}
