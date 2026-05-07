import SwiftUI

/// The prominent session title strip at the top of the conversation view.
/// Click-to-edit: click the name or pen icon to turn it into a TextField.
/// Press Enter OR click the green check to save. Escape cancels.
struct SessionHeaderView: View {
    @EnvironmentObject var appState: AppState

    @State private var isEditing = false
    @State private var draftTitle = ""
    @FocusState private var isFocused: Bool

    private var sessionInfo: SessionInfo? {
        guard let id = appState.selectedSessionId else { return nil }
        return appState.findSession(id: id)
    }

    private var originalTitle: String { sessionInfo?.title ?? "" }
    private var hasUnsavedRename: Bool { isEditing && draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) != originalTitle }

    /// The filesystem working directory the Claude Code session was started in.
    /// Pulled from the `cwd` field of the first entry in the JSONL — that's the
    /// source of truth, not the index file or the directory slug.
    private var actualCwd: String? {
        appState.currentConversation?.rawEntries
            .first(where: { $0.entry.cwd != nil })?.entry.cwd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1 — title, project chip, metadata, close
            HStack(spacing: 8) {
                if let s = sessionInfo, let project = projectFor(session: s) {
                    Text(project.name)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textFaint)
                }

                if isEditing {
                    editField
                } else {
                    displayTitle
                }

                Spacer()

                HStack(spacing: 10) {
                    LiveTailBadge()
                        .help("This conversation auto-updates as Claude Code writes to its JSONL file. Resume in your terminal and you'll see new messages appear here.")

                    if let m = appState.contextMetrics {
                        ContextBadge(metrics: m) {
                            appState.showContextSheet = true
                        }
                    }

                    if let s = sessionInfo {
                        Text(DateFormatting.dateString(s.modified))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    if let s = sessionInfo {
                        Button {
                            appState.presentVersions(for: s)
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 22, height: 22)
                                .background(Theme.surface2.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Versions · browse, diff, and restore previous on-disk versions of this session")
                    }

                    Button {
                        appState.closeCurrentSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Theme.surface2.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Close conversation · return to dashboard")
                }
            }

            // Row 2 — actual working directory
            if let cwd = actualCwd {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textFaint)
                    Text(cwd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help("Tap to copy path")
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cwd, forType: .string)
                            appState.showToast("Path copied")
                        }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.2)).frame(height: 1)
        }
    }

    // MARK: - Display state

    private var displayTitle: some View {
        HStack(spacing: 6) {
            Button {
                startEditing()
            } label: {
                Text(originalTitle.isEmpty ? "Untitled" : originalTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button { startEditing() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Rename session")
        }
    }

    // MARK: - Edit state

    private var editField: some View {
        HStack(spacing: 6) {
            TextField("", text: $draftTitle, onCommit: commitRename)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .focused($isFocused)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                .onExitCommand { cancelRename() }

            if hasUnsavedRename {
                Button(action: commitRename) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.successTint)
                        .frame(width: 22, height: 22)
                        .background(Theme.successTint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Save")
                .keyboardShortcut(.return, modifiers: [])
            }

            Button(action: cancelRename) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
    }

    // MARK: - Actions

    private func startEditing() {
        draftTitle = originalTitle
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != originalTitle {
            appState.renameCurrentSession(to: trimmed)
        }
        isEditing = false
    }

    private func cancelRename() {
        draftTitle = originalTitle
        isEditing = false
    }

    private func projectFor(session: SessionInfo) -> Project? {
        appState.projects.first { $0.sessions.contains { $0.id == session.id } }
    }
}

// MARK: - Context badge

/// A compact, clickable pill showing peak context fill. Opens the detail
/// sheet on click. Color fades green → amber → red as the window fills up.
struct ContextBadge: View {
    let metrics: ContextMetrics.Result
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(fillColor)
                    .frame(width: 6, height: 6)
                Text(metrics.peakContextTokens.formattedTokenCount)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text("/ \(metrics.contextWindowTokens.formattedTokenCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text("·  \(Int(metrics.fillRatio * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(fillColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(hovered ? fillColor.opacity(0.14) : Theme.surface2.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(fillColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
        .help("Context: \(metrics.peakContextTokens.formattedTokenCount) / \(metrics.contextWindowTokens.formattedTokenCount) · \(metrics.estimatedCostUSD.formattedCost) · click for breakdown")
    }

    private var fillColor: Color {
        switch metrics.fillRatio {
        case ..<0.5:  return Theme.successTint
        case ..<0.8:  return Theme.warnTint
        default:      return Theme.errorTint
        }
    }
}

// MARK: - Live tail badge

/// Visual cue that the open conversation is being watched on disk and
/// will auto-refresh when Claude Code writes new entries (e.g. when the
/// user resumes the session in their terminal). Pulses gently.
struct LiveTailBadge: View {
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.successTint)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            Text("live")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.successTint)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.successTint.opacity(0.1))
        .clipShape(Capsule())
        .onAppear { pulse = true }
    }
}
