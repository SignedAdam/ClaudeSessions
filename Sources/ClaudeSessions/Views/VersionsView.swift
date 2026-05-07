import SwiftUI
import AppKit

/// Sheet listing every previous version of one session. Source kinds are
/// distinguished by colored chips (live / save backup / vault / archive).
/// Up to two rows can be multi-selected for diff (click row 1, ⌘-click
/// row 2). The Diff button is enabled when exactly two rows are selected;
/// it opens `VersionDiffView` (T04). Restore opens a confirmation that
/// copies the chosen version into the project as a fresh sessionId (T05).
struct VersionsView: View {
    let sessionId: String
    let projectSlug: String?
    let projectCwd: String?       // resolved cwd, needed for Restore writes
    let sessionTitle: String
    @Binding var isPresented: Bool

    @EnvironmentObject var appState: AppState
    @State private var versions: [VersionHistoryService.Version] = []
    @State private var selected: Set<String> = []
    @State private var loading: Bool = true
    @State private var diffPair: (VersionHistoryService.Version, VersionHistoryService.Version)?
    @State private var pendingRestore: VersionHistoryService.Version?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 720, height: 540)
        .background(Theme.surface)
        .onAppear { reload() }
        .sheet(item: Binding(
            get: { diffPair.map { DiffPair(left: $0.0, right: $0.1) } },
            set: { if $0 == nil { diffPair = nil } }
        )) { pair in
            VersionDiffView(left: pair.left, right: pair.right,
                            isPresented: Binding(
                                get: { diffPair != nil },
                                set: { if !$0 { diffPair = nil } }
                            ))
                .environmentObject(appState)
        }
        .alert("Restore this version as a new session?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), presenting: pendingRestore) { v in
            Button("Restore") { performRestore(v) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { v in
            Text("Writes a fresh JSONL into the project with a new session id. The original version file is left untouched. The restored copy will appear in the sidebar as `\(sessionTitle) · restored from <ts>`.")
        }
    }

    /// Identifiable wrapper so `.sheet(item:)` can drive presentation.
    private struct DiffPair: Identifiable {
        let left: VersionHistoryService.Version
        let right: VersionHistoryService.Version
        var id: String { left.id + "|" + right.id }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.accent)
                    Text("Versions of \(sessionTitle)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Text("Every previous version of this session that exists on disk — live source, save-time backups, continuous-backup mirror snapshots, and archived copies.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark").foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if versions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.textTertiary)
                Text("No versions found")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("This session has no save backups, vault snapshots, or archive copies yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(versions) { version in
                        versionRow(version)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if selected.count == 0 {
                Text("Select two rows (⌘-click for the second) to compare.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            } else if selected.count == 1 {
                Text("\(selectedKindLabel) selected — ⌘-click another to compare, or restore as new.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("\(selected.count) selected. Click Diff to compare; Restore picks the first selection.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Reveal in Finder") { revealSelected() }
                .controlSize(.small)
                .disabled(selected.isEmpty)
            Button("Diff") { presentDiff() }
                .controlSize(.small)
                .disabled(selected.count != 2)
            Button("Restore as new…") { stageRestore() }
                .controlSize(.small)
                .disabled(selected.count != 1 || projectCwd == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Row

    @ViewBuilder
    private func versionRow(_ v: VersionHistoryService.Version) -> some View {
        let isSelected = selected.contains(v.id)

        Button { toggle(v.id) } label: {
            HStack(spacing: 12) {
                kindChip(v.kind)
                    .frame(width: 86, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(formatTimestamp(v.timestamp))
                            .font(.system(size: 11, weight: v.isCurrent ? .semibold : .regular))
                            .foregroundStyle(Theme.text)
                        if v.isCurrent {
                            Text("current")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accent.opacity(0.15))
                                .foregroundStyle(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text((v.filePath as NSString).lastPathComponent)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(formatBytes(v.size))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func kindChip(_ kind: VersionHistoryService.SourceKind) -> some View {
        let color = chipColor(kind)
        Text(kind.label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func chipColor(_ kind: VersionHistoryService.SourceKind) -> Color {
        switch kind {
        case .live:          return Theme.accent
        case .saveBackup:    return Theme.successTint
        case .vaultLive,
             .vaultSnapshot: return Theme.humanTint
        case .archive:       return Theme.warnTint
        }
    }

    // MARK: - Selection

    private func toggle(_ id: String) {
        if NSEvent.modifierFlags.contains(.command) {
            // ⌘-click: add or remove from selection (cap at 2)
            if selected.contains(id) {
                selected.remove(id)
            } else if selected.count < 2 {
                selected.insert(id)
            }
        } else {
            // Plain click: replace selection
            selected = [id]
        }
    }

    private var selectedKindLabel: String {
        guard let id = selected.first, let v = versions.first(where: { $0.id == id }) else { return "1" }
        return v.kind.label
    }

    // MARK: - Actions

    private func reload() {
        loading = true
        Task.detached(priority: .userInitiated) {
            let result = VersionHistoryService.versions(forSessionId: sessionId, projectSlug: projectSlug)
            await MainActor.run {
                versions = result
                loading = false
            }
        }
    }

    private func presentDiff() {
        guard selected.count == 2 else { return }
        let pair = versions.filter { selected.contains($0.id) }
        guard pair.count == 2 else { return }
        diffPair = (pair[0], pair[1])
    }

    private func stageRestore() {
        guard let id = selected.first,
              let v = versions.first(where: { $0.id == id }) else { return }
        pendingRestore = v
    }

    private func performRestore(_ version: VersionHistoryService.Version) {
        pendingRestore = nil
        guard let cwd = projectCwd else {
            appState.showToast("Cannot determine project directory")
            return
        }
        appState.restoreVersion(version, projectCwd: cwd, originalTitle: sessionTitle)
        isPresented = false
    }

    private func revealSelected() {
        guard let id = selected.first, let v = versions.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.selectFile(v.filePath, inFileViewerRootedAtPath: "")
    }

    // MARK: - Formatting

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}
