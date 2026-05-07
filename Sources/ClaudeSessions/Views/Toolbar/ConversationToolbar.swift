import SwiftUI

struct ConversationToolbar: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        HStack(spacing: 8) {
            // Filters — only make sense in Chat mode. In Reading, content is
            // already curated (human+claude text only). In JSON, everything
            // is shown as raw anyway.
            if isChatMode {
                HStack(spacing: 3) {
                    FilterPill(label: "human", isOn: $appState.showUserMessages, color: Theme.humanTint)
                    FilterPill(label: "claude", isOn: $appState.showAssistantMessages, color: Theme.accent)
                    FilterPill(label: "tools", isOn: $appState.showToolMessages, color: Theme.toolTint)
                    FilterPill(label: "sys", isOn: $appState.showSystemMessages, color: Theme.warnTint)
                }
            }

            Spacer()

            // Quick actions
            HStack(spacing: 3) {
                // Copy full transcript — everything including tools, system, etc.
                IconButton(icon: "text.alignleft") {
                    appState.copyFullTranscriptToClipboard()
                }
                .help("Copy full transcript · every message, tool call, result, and system event")

                // Copy cleaned dialogue only — just human ↔ Claude text
                IconButton(icon: "bubble.left.and.bubble.right") {
                    appState.extractToClipboard()
                }
                .help("Copy dialogue only · no tool calls, no system messages")

                // Branded one-click export to another agent. Primary = the
                // user's most-used target (Codex by default). Chevron opens
                // a popover with all four. The full export sheet is still
                // reachable via the contextMenu on the extract button.
                ExportToAgentButton()

                // Primary action: fork the dialogue-only version into a new
                // Claude session. Renamed from "extract" — that name was
                // ambiguous against the two copy buttons which also extract.
                QuickAction(
                    icon: appState.extractMode == .newSession ? "sparkles" : "arrow.up.forward.app",
                    label: extractLabel,
                    accent: Theme.accent
                ) {
                    appState.extractAndOpenInClaude()
                }
                .help(extractTooltip)
                .contextMenu {
                    Button("Open as New Session (recommended)") {
                        if let conv = appState.currentConversation,
                           let cwd = conv.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd {
                            appState.extractAsNewSession(conversation: conv, cwd: cwd)
                        }
                    }
                    Button("Open as Piped Prompt (fresh context)") {
                        if let conv = appState.currentConversation,
                           let cwd = conv.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd {
                            appState.extractAsPipedPrompt(conversation: conv, cwd: cwd)
                        }
                    }
                    Divider()
                    Button("Open Export Sheet…") {
                        appState.showExportSheet = true
                    }
                    Button("Change default in Settings…") {
                        openSettingsAction()
                    }
                }

                // Before → after transformation hint. Explicit both-numbers
                // so it can't be mistaken for "saved" vs "result".
                if let m = appState.contextMetrics,
                   m.dialogueTokenEstimate > 0,
                   m.peakContextTokens > 0 {
                    cleanTransformPill(from: m.peakContextTokens,
                                       to: m.dialogueTokenEstimate)
                }

                // Resume current session as-is
                if let cwd = projectPath {
                    QuickAction(icon: "terminal", label: "resume") {
                        if let sid = appState.selectedSessionId {
                            ProcessLauncher.resumeSession(sessionId: sid, cwd: cwd)
                        }
                    }
                    .help("Resume this session in Claude Code (full history, tools and all)")
                }
            }

            Divider().frame(height: 14).opacity(0.3)

            // Chat / Reading / JSON mode
            HStack(spacing: 0) {
                ModePill(label: "chat", active: !appState.isJSONMode && !appState.isReadingMode) {
                    appState.isJSONMode = false
                    appState.isReadingMode = false
                }
                ModePill(label: "reading", active: appState.isReadingMode && !appState.isJSONMode) {
                    appState.isJSONMode = false
                    appState.isReadingMode = true
                }
                ModePill(label: "json", active: appState.isJSONMode) {
                    appState.isJSONMode = true
                }
            }
            .padding(2)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // Save indicator
            if appState.isDirty {
                Button { Task { await appState.save() } } label: {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.warnTint).frame(width: 4, height: 4)
                        Text("save")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.warnTint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.warnTint.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.warnTint.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.2)).frame(height: 1) }
    }

    private var projectPath: String? {
        guard let conv = appState.currentConversation else { return nil }
        let recorded = conv.rawEntries.first(where: { $0.entry.cwd != nil })?.entry.cwd
        let slug = (conv.filePath as NSString).deletingLastPathComponent
        return SlugResolver.bestCwd(
            slug: (slug as NSString).lastPathComponent,
            recorded: recorded
        )
    }

    private var isChatMode: Bool {
        !appState.isJSONMode && !appState.isReadingMode
    }

    /// "current-peak → cleaned-size" pill. Explicit both-numbers so the user
    /// doesn't have to guess which number means which.
    @ViewBuilder
    private func cleanTransformPill(from peak: Int, to cleaned: Int) -> some View {
        let savings = peak > 0 ? Int(Double(peak - cleaned) / Double(peak) * 100) : 0
        HStack(spacing: 4) {
            Text(peak.formattedTokenCount)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(cleaned.formattedTokenCount)
                .foregroundStyle(Theme.accent)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.accent.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
        )
        .help("After cleaning: \(cleaned.formattedTokenCount) tokens (trimmed ~\(savings)% from the \(peak.formattedTokenCount) peak)")
    }

    private var extractLabel: String {
        appState.extractMode == .newSession ? "clean ↗" : "clean · pipe ↗"
    }

    private var extractTooltip: String {
        switch appState.extractMode {
        case .newSession:
            return "Fork a clean copy (just the human↔Claude dialogue) into a new resumable Claude Code session"
        case .pipedPrompt:
            return "Pipe the cleaned dialogue into a fresh Claude Code session as its first prompt"
        }
    }
}

// MARK: - Components

/// Filter pill — toggle style. Clear on/off state, color-coded, always readable.
struct FilterPill: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color

    @State private var hovered = false

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.1)) { isOn.toggle() } } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? color : Theme.textTertiary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(
                    isOn
                        ? color.opacity(0.18)
                        : (hovered ? Theme.surface2 : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isOn ? color.opacity(0.45) : Theme.border.opacity(0.5),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}

/// Icon-only toolbar button. Used when the icon is self-explanatory and
/// labeling it would clutter the header.
struct IconButton: View {
    let icon: String
    var accent: Color? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent ?? (hovered ? Theme.text : Theme.textSecondary))
                .frame(width: 26, height: 22)
                .background(hovered ? Theme.surface2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}

/// Action pill — button style. Distinct from filters: filled on hover,
/// accent ring when accented, more prominent.
struct QuickAction: View {
    let icon: String
    let label: String
    var accent: Color? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(
                accent
                    ?? (hovered ? Theme.text : Theme.textSecondary)
            )
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(
                accent != nil
                    ? accent!.opacity(hovered ? 0.22 : 0.14)
                    : (hovered ? Theme.surface2 : Theme.surface2.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        accent != nil
                            ? accent!.opacity(0.4)
                            : Theme.border.opacity(0.5),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}

/// Mode pill — segmented-control segment. Active state reads as firmly
/// pressed/selected, inactive as cleanly available.
struct ModePill: View {
    let label: String
    let active: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: active ? .bold : .medium, design: .monospaced))
                .foregroundStyle(active ? Theme.accent : (hovered ? Theme.text : Theme.textTertiary))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(active ? Theme.accent.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}
