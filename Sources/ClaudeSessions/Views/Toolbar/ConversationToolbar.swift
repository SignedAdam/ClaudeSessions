import SwiftUI

struct ConversationToolbar: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        HStack(spacing: 8) {
            // Filters live in their own segmented container — multi-select,
            // tight, visually paired with the chat/reading/json segment on
            // the right. Only meaningful in Chat mode (Reading curates and
            // JSON shows raw).
            if isChatMode {
                filterSegment
            }

            Spacer()

            // Right-side action cluster collapses progressively as the
            // window narrows. Three tiers, picked by ViewThatFits.
            ViewThatFits(in: .horizontal) {
                wideActions
                mediumActions
                narrowActions
            }

            Divider().frame(height: 14).opacity(0.3)

            modeSegment

            // Save indicator (contextual — only when dirty).
            if appState.isDirty {
                saveIndicator
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.2)).frame(height: 1)
        }
    }

    // MARK: - Filter segment

    /// Multi-select segmented container. Each segment is independently
    /// toggleable. Visually paired with the chat/reading/json segment so
    /// the user reads them as siblings.
    private var filterSegment: some View {
        HStack(spacing: 0) {
            FilterSegmentItem(label: "human",
                              isOn: $appState.showUserMessages,
                              color: Theme.humanTint)
            FilterSegmentItem(label: "claude",
                              isOn: $appState.showAssistantMessages,
                              color: Theme.accent)
            FilterSegmentItem(label: "tools",
                              isOn: $appState.showToolMessages,
                              color: Theme.toolTint)
            FilterSegmentItem(label: "sys",
                              isOn: $appState.showSystemMessages,
                              color: Theme.warnTint)
        }
        .padding(2)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Action cluster (three tiers)

    /// Wide: every action visible inline, plus the metric pill.
    private var wideActions: some View {
        HStack(spacing: 3) {
            copyFullButton
            copyDialogueButton
            selectButton
            ExportToAgentButton()
            supercompactButton
            tokenMetricPill
            resumeButton
        }
    }

    /// Medium: the three icon-buttons collapse into an overflow menu;
    /// export, supercompact, token pill, resume stay inline.
    private var mediumActions: some View {
        HStack(spacing: 3) {
            overflowMenu(items: .secondary)
            ExportToAgentButton()
            supercompactButton
            tokenMetricPill
            resumeButton
        }
    }

    /// Narrow: only the headline action stays inline; everything else
    /// (including resume) is in the overflow menu. Token pill drops.
    private var narrowActions: some View {
        HStack(spacing: 3) {
            overflowMenu(items: .all)
            supercompactButton
        }
    }

    // MARK: - Mode segment

    private var modeSegment: some View {
        HStack(spacing: 0) {
            ModePill(label: "chat",
                     active: !appState.isJSONMode && !appState.isReadingMode) {
                appState.isJSONMode = false
                appState.isReadingMode = false
            }
            ModePill(label: "reading",
                     active: appState.isReadingMode && !appState.isJSONMode) {
                appState.isJSONMode = false
                appState.isReadingMode = true
            }
            ModePill(label: "json",
                     active: appState.isJSONMode) {
                appState.isJSONMode = true
            }
        }
        .padding(2)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Individual buttons

    private var copyFullButton: some View {
        IconButton(icon: "text.alignleft") {
            appState.copyFullTranscriptToClipboard()
        }
        .help("Copy full transcript · every message, tool call, result, and system event")
    }

    private var copyDialogueButton: some View {
        IconButton(icon: "bubble.left.and.bubble.right") {
            appState.extractToClipboard()
        }
        .help("Copy dialogue only · no tool calls, no system messages")
    }

    private var selectButton: some View {
        IconButton(icon: "checkmark.circle") {
            appState.enterSelectMode()
        }
        .help("Pick specific messages · enter select mode")
    }

    private var supercompactButton: some View {
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
            Button("Open Export Sheet…") { appState.showExportSheet = true }
            Button("Change default in Settings…") { openSettingsAction() }
        }
    }

    @ViewBuilder
    private var resumeButton: some View {
        if let cwd = projectPath {
            QuickAction(icon: "terminal", label: "resume") {
                if let sid = appState.selectedSessionId {
                    ProcessLauncher.resumeSession(sessionId: sid, cwd: cwd)
                }
            }
            .help("Resume this session in Claude Code (full history, tools and all)")
        }
    }

    @ViewBuilder
    private var tokenMetricPill: some View {
        if let m = appState.contextMetrics,
           m.dialogueTokenEstimate > 0,
           m.peakContextTokens > 0 {
            cleanTransformPill(from: m.peakContextTokens, to: m.dialogueTokenEstimate)
        }
    }

    private var saveIndicator: some View {
        Button { Task { await appState.save() } } label: {
            HStack(spacing: 4) {
                Circle().fill(Theme.warnTint).frame(width: 4, height: 4)
                Text("save")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Theme.warnTint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.warnTint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.warnTint.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overflow menu

    private enum OverflowItems { case secondary, all }

    @ViewBuilder
    private func overflowMenu(items: OverflowItems) -> some View {
        Menu {
            Button {
                appState.copyFullTranscriptToClipboard()
            } label: {
                Label("Copy full transcript", systemImage: "text.alignleft")
            }
            Button {
                appState.extractToClipboard()
            } label: {
                Label("Copy dialogue only", systemImage: "bubble.left.and.bubble.right")
            }
            Button {
                appState.enterSelectMode()
            } label: {
                Label("Pick specific messages…", systemImage: "checkmark.circle")
            }
            if items == .all {
                Divider()
                Button {
                    appState.showExportSheet = true
                } label: {
                    Label("Export to agent…", systemImage: "square.and.arrow.up")
                }
                if let cwd = projectPath, let sid = appState.selectedSessionId {
                    Button {
                        ProcessLauncher.resumeSession(sessionId: sid, cwd: cwd)
                    } label: {
                        Label("Resume in terminal", systemImage: "terminal")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 22)
                .background(Theme.surface2.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.border.opacity(0.5), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Helpers

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

    /// Information chip — current peak vs cleaned size. Softer treatment
    /// than the action buttons so the eye reads it as info, not action.
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
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(height: 22)
        .background(Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help("After cleaning: \(cleaned.formattedTokenCount) tokens (trimmed ~\(savings)% from the \(peak.formattedTokenCount) peak)")
    }

    private var extractLabel: String {
        appState.extractMode == .newSession ? "supercompact ↗" : "supercompact · pipe ↗"
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

/// One segment in the multi-select filter container. Mirrors the visual
/// language of `ModePill` (tight, padded inside a rounded surface) but
/// each instance has its own independent on/off state.
struct FilterSegmentItem: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color

    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.1)) { isOn.toggle() }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isOn ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isOn ? color : (hovered ? Theme.text : Theme.textTertiary))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isOn ? color.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}

/// Icon-only toolbar button. Bordered surface so it sits visually next to
/// QuickAction buttons without looking unfinished.
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
                .background(hovered ? Theme.surface2 : Theme.surface2.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.border.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
    }
}

/// Action pill — icon + label, optionally accented. 22pt tall to match
/// IconButton, 5pt corner radius to match the rest of the cluster.
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
                accent ?? (hovered ? Theme.text : Theme.textSecondary)
            )
            .padding(.horizontal, 9).padding(.vertical, 0)
            .frame(height: 22)
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

/// One segment in the chat/reading/json mode container.
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
