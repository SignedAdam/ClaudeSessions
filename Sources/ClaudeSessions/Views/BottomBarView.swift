import SwiftUI
import AppKit

/// The always-visible bottom bar. Left side shows conversation stats (when a
/// conversation is open). Right side hosts theme + settings, always clickable.
///
/// Labels are explicit so metrics read at a glance: `human 12   claude 41
/// tools 37   1h 23m`. Unlike the titlebar region, this area has no drag
/// conflict so buttons just work.
struct BottomBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeStore: ThemeStore
    @Binding var showThemePicker: Bool
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        HStack(spacing: 18) {
            if let conv = appState.currentConversation {
                labeledMetric("human",
                              count: conv.stats.userMessageCount,
                              color: Theme.humanTint)
                labeledMetric("claude",
                              count: conv.stats.assistantMessageCount,
                              color: Theme.accent)
                labeledMetric("tools",
                              count: conv.stats.toolCallCount,
                              color: Theme.toolTint)
                if let duration = conv.stats.duration {
                    labeledDuration(duration)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("no conversation open")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            // Global controls — always accessible
            HStack(spacing: 4) {
                TopBarIcon(icon: "paintpalette") { showThemePicker.toggle() }
                    .help("Theme & ambience")
                TopBarIcon(icon: "gearshape") { openSettings() }
                    .help("Settings (⌘,)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)
        }
    }

    // MARK: - Metric pieces

    private func labeledMetric(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .help("\(label): \(count)")
    }

    private func labeledDuration(_ interval: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Text("duration")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Text(DateFormatting.durationString(interval))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
        .help("Session duration")
    }

    // MARK: - Actions

    private func openSettings() {
        // SwiftUI 14+ environment action is the canonical way to open the
        // Settings scene; the older sendAction(showSettingsWindow:) path
        // doesn't always find a target in single-window apps.
        openSettingsAction()
    }
}
