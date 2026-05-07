import SwiftUI

/// Split button: primary action exports to the user's most-used agent
/// (or Codex by default). The chevron half opens a popover with the
/// remaining options, each rendered with its own brand styling.
struct ExportToAgentButton: View {
    @EnvironmentObject var appState: AppState
    @State private var showMenu = false
    @State private var hovered: Half = .none

    private enum Half { case primary, chevron, none }

    var body: some View {
        let primary = appState.defaultAgentTarget

        HStack(spacing: 0) {
            // Primary half — branded wordmark for the most-used target
            Button {
                appState.exportToAgent(primary)
            } label: {
                primaryLabel(target: primary)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? .primary : .none }
            .help("Export this conversation to \(primary.displayName) · \(primary.tagline)")

            // Hairline divider between the halves
            Rectangle()
                .fill(primary.brandColor.opacity(0.3))
                .frame(width: 1, height: 18)

            // Chevron half — opens the full agent menu
            Button { showMenu.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(primary.brandColor)
                    .frame(width: 18, height: 22)
                    .background(hovered == .chevron ? primary.brandColor.opacity(0.18) : primary.brandColor.opacity(0.10))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? .chevron : .none }
            .help("Choose another agent")
            .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                AgentMenuPopover(
                    onSelect: { target in
                        showMenu = false
                        appState.exportToAgent(target)
                    },
                    primary: primary
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(primary.brandColor.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func primaryLabel(target: AgentTarget) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(target.brandColor)
            Text("export to")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            BrandedWordmark(target: target)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
            target.brandColor.opacity(hovered == .primary ? 0.18 : 0.10)
        )
    }
}

// MARK: - Branded wordmark

/// A target's display name styled in its own brand colors. Used both in
/// the primary button label and the menu popover rows.
struct BrandedWordmark: View {
    let target: AgentTarget

    var body: some View {
        let name = target.lowercaseWordmark ? target.displayName.lowercased() : target.displayName
        Text(name)
            .font(target.wordmarkFont)
            .foregroundStyle(target.brandGradient)
    }
}

// MARK: - Popover menu

private struct AgentMenuPopover: View {
    let onSelect: (AgentTarget) -> Void
    let primary: AgentTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("send conversation to")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            ForEach(AgentTarget.allCases) { target in
                AgentRow(target: target, isPrimary: target == primary) {
                    onSelect(target)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .frame(width: 280)
        .background(Theme.surface)
    }
}

private struct AgentRow: View {
    let target: AgentTarget
    let isPrimary: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Brand glyph in a tinted square — keeps each row's identity
                // anchored before the eye even reads the wordmark.
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(target.brandGradient)
                        .opacity(0.85)
                    Image(systemName: target.glyph)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        BrandedWordmark(target: target)
                        if isPrimary {
                            Text("default")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Theme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(target.tagline)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(hovered ? target.brandColor.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
