import SwiftUI
import AppKit
import ContinuousBackup

/// Browse the contents of `~/.ClaudeSessions/backup/projects/` and restore
/// any conversation back into Claude Code's project tree. Lists every
/// backed-up file, including rotated `.orig-<ts>` snapshots, grouped by
/// session. Sessions whose original file no longer exists in
/// `~/.claude/projects/` (deleted by `cleanupPeriodDays`, manually removed,
/// etc.) float to the top — those are the most likely restore targets.
struct BackupVaultView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState

    @State private var groups: [(slug: String, sessionId: String, entries: [BackupVaultService.Entry])] = []
    @State private var search: String = ""
    @State private var hideStillPresent: Bool = false
    @State private var pendingRestore: BackupVaultService.Entry?
    @State private var restoreError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            controls
            Divider().opacity(0.3)
            content
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 720, height: 540)
        .background(Theme.surface)
        .onAppear { reload() }
        .alert("Restore this conversation?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), presenting: pendingRestore) { entry in
            Button("Restore") { performRestore(entry) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { entry in
            Text(restoreMessage(for: entry))
        }
        .alert("Restore failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        ), presenting: restoreError) { _ in
            Button("OK", role: .cancel) { restoreError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(Theme.accent)
                    Text("Backup Vault")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Text("~/.ClaudeSessions/backup/projects/ — preserved even when Claude Code deletes the source.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            TextField("Search by session id or project slug…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            Toggle("Only missing originals", isOn: $hideStillPresent)
                .toggleStyle(.switch)
                .controlSize(.small)
            Button("Refresh") { reload() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        let visible = filtered
        if visible.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.textTertiary)
                Text(groups.isEmpty
                     ? "No backups yet. The continuous backup engine fills this folder as it runs."
                     : "No matches for the current filter.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible, id: \.sessionId) { group in
                        sessionGroup(group)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(filtered.count) of \(groups.count) sessions shown")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil,
                                              inFileViewerRootedAtPath: BackupEngine.backupMirrorRoot.path)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Session group row

    @ViewBuilder
    private func sessionGroup(_ group: (slug: String, sessionId: String, entries: [BackupVaultService.Entry])) -> some View {
        let sourceMissing = group.entries.first?.sourceExists == false
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: sourceMissing ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(sourceMissing ? Theme.warnTint : Theme.successTint)
                    .font(.system(size: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.sessionId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(group.slug)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if sourceMissing {
                    Text("source deleted")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.warnTint.opacity(0.15))
                        .foregroundStyle(Theme.warnTint)
                        .clipShape(Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.entries, id: \.id) { entry in
                    versionRow(entry)
                }
            }
            .padding(.leading, 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Theme.surface2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func versionRow(_ entry: BackupVaultService.Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isSnapshot ? "clock.arrow.circlepath" : "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isSnapshot
                     ? "snapshot · rotated \(formatTimestamp(entry.snapshotTimestamp ?? entry.modifiedAt))"
                     : "live mirror · last sync \(formatTimestamp(entry.modifiedAt))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(formatBytes(entry.size))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Restore") { pendingRestore = entry }
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func reload() {
        let entries = BackupVaultService.listEntries()
        groups = BackupVaultService.groupBySession(entries)
    }

    private var filtered: [(slug: String, sessionId: String, entries: [BackupVaultService.Entry])] {
        let q = search.lowercased()
        return groups.filter { group in
            if hideStillPresent && (group.entries.first?.sourceExists == true) {
                return false
            }
            if q.isEmpty { return true }
            return group.sessionId.lowercased().contains(q)
                || group.slug.lowercased().contains(q)
        }
    }

    private func restoreMessage(for entry: BackupVaultService.Entry) -> String {
        let target = "\(BackupEngine.sourceRoot)/\(entry.projectSlug)/\(entry.sessionId).jsonl"
        if entry.sourceExists {
            return "The original session file already exists at:\n\(target)\n\nThis restore will be aborted to avoid overwriting it. To restore anyway, first move or rename the original."
        }
        return "Will copy the backup back to:\n\(target)\n\nThe restored session will appear in Claude Code's project once it next scans the directory."
    }

    private func performRestore(_ entry: BackupVaultService.Entry) {
        pendingRestore = nil
        do {
            let url = try BackupVaultService.restore(entry: entry)
            appState.showToast("Restored to \(url.lastPathComponent)")
            Task { await appState.loadProjects() }
        } catch {
            restoreError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}
