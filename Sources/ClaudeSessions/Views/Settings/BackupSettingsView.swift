import SwiftUI
import AppKit
import ContinuousBackup

/// Settings surface for the continuous backup engine.
/// Lets the user turn it on/off, see stats, and jump to the backup folder.
struct BackupSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // Forward to a content view that can @ObservedObject the engine.
        // SwiftUI re-renders when the engine publishes.
        BackupSettingsContent(engine: appState.backupEngine)
            .environmentObject(appState)
    }
}

private struct BackupSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var engine: BackupEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            enableToggle
            if engine.isBootstrapping { bootstrappingRow }
            if engine.lowDiskSpace { lowDiskRow }
            Divider()
            statsGrid
            Divider()
            locationRow
            if let err = engine.lastError { errorRow(err) }
            Spacer()
            footer
        }
        .padding()
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Continuous Backup")
                    .font(.system(size: 14, weight: .semibold))
                Text("Mirror every conversation into ~/.ClaudeSessions/ so Claude Code's 30-day auto-delete can't touch them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var enableToggle: some View {
        Toggle(isOn: Binding(
            get: { appState.continuousBackupEnabled },
            set: { appState.setContinuousBackupEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Enable continuous backup")
                    .font(.system(size: 12, weight: .medium))
                Text(engine.isRunning ? "Running · watching ~/.claude/projects/" : "Paused")
                    .font(.system(size: 10))
                    .foregroundStyle(engine.isRunning ? .green : .secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var bootstrappingRow: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Initial scan in progress — working through existing sessions…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var lowDiskRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Low free disk space — backup is paused until space is available.")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        }
    }

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow(label: "Files backed up", value: "\(engine.trackedFiles)")
            statRow(label: "Active sources", value: "\(engine.livingSourceFiles)")
            statRow(
                label: "Preserved (deleted by Claude Code)",
                value: "\(engine.orphanedBackupFiles)",
                emphasized: engine.orphanedBackupFiles > 0
            )
            statRow(label: "Backup size", value: formatBytes(engine.totalBackupBytes))
            statRow(label: "Last sync", value: formatDate(engine.lastSyncAt))
        }
        .font(.system(size: 11))
    }

    private var locationRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Location:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("~/.ClaudeSessions/backup/")
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            Button("Reveal in Finder") {
                let path = BackupEngine.backupMirrorRoot.path
                let fm = FileManager.default
                if !fm.fileExists(atPath: path) {
                    try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
                }
                NSWorkspace.shared.selectFile(
                    path,
                    inFileViewerRootedAtPath: BackupEngine.backupHome.path
                )
            }
            .controlSize(.small)
        }
    }

    private func errorRow(_ err: String) -> some View {
        Text("Last error: \(err)")
            .font(.system(size: 10))
            .foregroundStyle(.red)
            .lineLimit(2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How it works")
                .font(.system(size: 11, weight: .semibold))
            Text("Only new bytes are copied — when a session grows, only the new lines are appended to its backup copy. Files are never deleted from the backup, even if Claude Code removes the original. ~/.ClaudeSessions/ is just a folder — copy it wherever you like.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stat row

    @ViewBuilder
    private func statRow(label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
