import SwiftUI

/// One-page first-launch wizard. Two protective recommendations against
/// losing Claude Code conversations:
///
/// 1. Extend `cleanupPeriodDays` so Claude Code's auto-delete (30 days
///    by default) doesn't take old transcripts.
/// 2. Install the background backup daemon (LaunchAgent) so backups
///    happen even when this app isn't running.
///
/// Each item has Yes / Skip. Closing the sheet (via Done) persists a
/// `didShowOnboarding` flag so we never show this again.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var configStore = ClaudeCodeConfigStore()

    @State private var retentionState: ItemState = .pending
    @State private var daemonState: ItemState = .pending
    @State private var daemonError: String?

    enum ItemState {
        case pending, applying, applied, skipped, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    retentionCard
                    daemonCard
                }
                .padding(20)
            }
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 560, height: 600)
        .background(Theme.surface)
        .onAppear { configStore.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                Text("Welcome to Claude Sessions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Text("Two quick recommendations to protect your conversations from being silently lost. You can revisit both later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Card 1: retention

    private var retentionCard: some View {
        Card(
            iconName: "calendar.badge.clock",
            title: "Extend session retention",
            description: "Claude Code auto-deletes its session transcripts after \(configStore.cleanupPeriodDaysText.isEmpty ? "30" : configStore.cleanupPeriodDaysText) days by default. Setting this to a very high number (36500 ≈ 100 years) effectively turns it off, so old conversations stay in `~/.claude/projects/` for as long as you keep them.",
            state: retentionState,
            error: nil,
            primaryAction: {
                applyRetention()
            },
            primaryLabel: "Set to 36500 days",
            skipAction: {
                retentionState = .skipped
            },
            doneLabel: "Done — retention extended",
            skippedLabel: "Skipped"
        )
    }

    private func applyRetention() {
        retentionState = .applying
        configStore.cleanupPeriodDaysText = "36500"
        configStore.applyCleanupDays()
        retentionState = (configStore.lastError == nil) ? .applied : .failed
    }

    // MARK: - Card 2: backup daemon

    private var daemonCard: some View {
        Card(
            iconName: "externaldrive.badge.timemachine",
            title: "Install the background backup daemon",
            description: "A small companion process that mirrors `~/.claude/projects/` into `~/.ClaudeSessions/backup/` whenever your Mac is awake — even when this app is closed. The mirror is append-only, so files Claude Code deletes on its own are still preserved.",
            state: daemonState,
            error: daemonError,
            primaryAction: {
                installDaemon()
            },
            primaryLabel: "Install LaunchAgent",
            skipAction: {
                daemonState = .skipped
            },
            doneLabel: "Done — daemon running",
            skippedLabel: "Skipped"
        )
    }

    private func installDaemon() {
        daemonState = .applying
        daemonError = nil
        // Run off the main thread so the spinner can render.
        Task.detached {
            do {
                try LaunchAgentInstaller.install()
                await MainActor.run {
                    daemonState = .applied
                }
            } catch {
                await MainActor.run {
                    daemonError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    daemonState = .failed
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("You can change either of these later in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button("Done") {
                UserDefaults.standard.set(true, forKey: "didShowOnboarding")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Reusable card

private struct Card: View {
    let iconName: String
    let title: String
    let description: String
    let state: OnboardingView.ItemState
    let error: String?
    let primaryAction: () -> Void
    let primaryLabel: String
    let skipAction: () -> Void
    let doneLabel: String
    let skippedLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
            if let error {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.errorTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                switch state {
                case .pending:
                    Button("Skip", action: skipAction)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    Button(primaryLabel, action: primaryAction)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                case .applying:
                    ProgressView().controlSize(.small)
                    Text("Working…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                case .applied:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.successTint)
                    Text(doneLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.successTint)
                case .skipped:
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Theme.textTertiary)
                    Text(skippedLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    Button("Apply now", action: primaryAction)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.errorTint)
                    Button("Retry", action: primaryAction)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    Button("Skip", action: skipAction)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.border.opacity(0.4), lineWidth: 1)
        )
    }
}
