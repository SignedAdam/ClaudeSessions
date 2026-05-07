import SwiftUI

/// Detailed context-usage view inspired by Claude Code's `/context` command.
///
/// Shows the peak context as a colored grid, with a legend below breaking
/// down where the tokens went: messages, tools, system, overhead, free.
/// Cost estimate, cache savings, and per-message totals.
struct ContextDetailView: View {
    let metrics: ContextMetrics.Result
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    grid
                    breakdown
                    moneyAndCache
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 620)
        .background(Theme.surface)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
            Text("Context Usage")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let model = metrics.model {
                Text(model.replacingOccurrences(of: "claude-", with: ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Capsule())
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.surface.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(metrics.peakContextTokens.formattedTokenCount)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(fillColor)
                Text("/ \(metrics.contextWindowTokens.formattedTokenCount)")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text("tokens")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(Int(metrics.fillRatio * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(fillColor)
            }
            Text("peak context ever sent to the model in this session")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Colored grid of 500 cells (50 x 10), each representing ~0.2% of the
    /// window. Cells are colored by the category occupying that token range.
    private var grid: some View {
        let totalCells = 500
        let cols = 50
        let breakdown = metrics.breakdown
        let window = metrics.contextWindowTokens

        // Ordered segments (category, tokens). Order matches the grid fill.
        let segments: [(label: String, tokens: Int, color: Color)] = [
            ("system",     breakdown.system,              Theme.warnTint),
            ("overhead",   breakdown.overhead,            Theme.accentDim),
            ("tool calls", breakdown.toolCalls,           Theme.toolTint),
            ("tool results", breakdown.toolResults,       Theme.toolTint.opacity(0.6)),
            ("you",        breakdown.userMessages,        Theme.humanTint),
            ("claude",     breakdown.assistantMessages,   Theme.accent),
        ]

        // Compute how many cells each segment takes
        var cellColors: [Color] = []
        for seg in segments {
            let share = window > 0 ? Double(seg.tokens) / Double(window) : 0
            let count = Int((share * Double(totalCells)).rounded())
            cellColors.append(contentsOf: Array(repeating: seg.color, count: count))
        }
        // Cap at totalCells, then pad remainder with "free"
        cellColors = Array(cellColors.prefix(totalCells))
        let freeCount = totalCells - cellColors.count
        let freeCells = Array(repeating: Color.clear, count: freeCount)
        cellColors.append(contentsOf: freeCells)

        return VStack(alignment: .leading, spacing: 6) {
            Text("CONTEXT MAP")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)

            let rows = (0..<(totalCells / cols))
            VStack(spacing: 2) {
                ForEach(Array(rows), id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { col in
                            let i = row * cols + col
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(cellColors[i])
                                .overlay(
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .strokeBorder(
                                            cellColors[i] == .clear ? Theme.border.opacity(0.3) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                                .frame(height: 9)
                        }
                    }
                }
            }
        }
    }

    private var breakdown: some View {
        let b = metrics.breakdown
        return VStack(alignment: .leading, spacing: 8) {
            Text("BREAKDOWN")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 5) {
                breakdownRow(color: Theme.humanTint,
                             label: "you (messages)",
                             tokens: b.userMessages)
                breakdownRow(color: Theme.accent,
                             label: "claude (messages)",
                             tokens: b.assistantMessages)
                breakdownRow(color: Theme.toolTint,
                             label: "tool calls",
                             tokens: b.toolCalls)
                breakdownRow(color: Theme.toolTint.opacity(0.6),
                             label: "tool results",
                             tokens: b.toolResults)
                breakdownRow(color: Theme.warnTint,
                             label: "system messages",
                             tokens: b.system)
                breakdownRow(color: Theme.accentDim,
                             label: "overhead (system prompt, tools, memory)",
                             tokens: b.overhead,
                             isApproximate: true)
                breakdownRow(color: Color.clear,
                             label: "free space",
                             tokens: b.free,
                             borderOnly: true)
            }
        }
    }

    private func breakdownRow(
        color: Color,
        label: String,
        tokens: Int,
        isApproximate: Bool = false,
        borderOnly: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(borderOnly ? Theme.border : Color.clear, lineWidth: 1)
                )

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
            if isApproximate {
                Text("(approx.)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("\(tokens.formattedTokenCount)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Text(percentString(tokens: tokens))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private func percentString(tokens: Int) -> String {
        let pct = Double(tokens) / Double(metrics.contextWindowTokens) * 100
        return String(format: "%.1f%%", pct)
    }

    private var moneyAndCache: some View {
        HStack(spacing: 12) {
            statCard(
                label: "estimated cost",
                value: metrics.estimatedCostUSD.formattedCost,
                color: Theme.accent
            )
            statCard(
                label: "output",
                value: metrics.totalOutputTokens.formattedTokenCount,
                color: Theme.accent
            )
            statCard(
                label: "cache hit rate",
                value: String(format: "%.0f%%", metrics.cacheHitRate * 100),
                color: Theme.successTint
            )
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.border.opacity(0.4), lineWidth: 1)
        )
    }

    /// Color the "X%" number by how alarming the fill is.
    private var fillColor: Color {
        switch metrics.fillRatio {
        case ..<0.5:  return Theme.successTint
        case ..<0.8:  return Theme.warnTint
        default:      return Theme.errorTint
        }
    }
}
