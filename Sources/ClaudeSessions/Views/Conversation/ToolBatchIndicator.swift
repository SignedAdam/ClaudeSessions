import SwiftUI

/// A thin in-line marker that represents a collapsed group of tool calls /
/// tool results / system messages in Reading Mode.
///
/// Visual: two faint dashed rules framing a pill with a count.
/// On hover, an "unhide" hint fades in in a reserved slot — NO layout
/// shift. Clicking expands *just this batch*, not every hidden batch.
struct ToolBatchIndicator: View {
    let count: Int
    let isExpanded: Bool       // kept for symmetry; caller decides whether to show us
    let onToggle: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                // Left dashed rule
                dashedRule

                // Center pill
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down.circle")
                        .font(.system(size: 9, weight: .medium))
                    Text("\(count) tool call\(count == 1 ? "" : "s") hidden")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(hovered ? Theme.accent : Theme.textTertiary)

                // Reserved hint slot — always laid out; fades in on hover.
                Text("click to reveal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .opacity(hovered ? 1 : 0)
                    .frame(width: 90, alignment: .leading)

                // Right dashed rule
                dashedRule
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }

    private var dashedRule: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(
                hovered ? Theme.accent.opacity(0.35) : Theme.border,
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
        .frame(height: 1)
    }
}
