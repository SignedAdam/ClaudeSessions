import SwiftUI

/// Trash-bin-style view of archived sessions.
/// Lists them by archived date (newest first), with per-row restore and
/// permanent-delete actions via right-click.
struct ArchiveView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeStore: ThemeStore
    @Binding var isPresented: Bool

    @State private var entries: [ArchiveService.ArchivedEntry] = []
    @State private var pendingDelete: ArchiveService.ArchivedEntry?
    @State private var query: String = ""

    private var filtered: [ArchiveService.ArchivedEntry] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter {
            $0.title.lowercased().contains(q) ||
            $0.originalProjectName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar

            Divider()

            if entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 600, height: 540)
        .background(Theme.surface)
        .onAppear { reload() }
        .alert(item: $pendingDelete) { entry in
            Alert(
                title: Text("Permanently delete this session?"),
                message: Text("\(entry.title)\n\nThis cannot be undone."),
                primaryButton: .destructive(Text("Delete Forever")) {
                    appState.permanentlyDeleteArchived(entry)
                    reload()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text("Archive")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(entries.count) session\(entries.count == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
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
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            TextField("filter archived…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface2.opacity(0.5))
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { entry in
                    row(for: entry)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func row(for entry: ArchiveService.ArchivedEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(entry.originalProjectName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(Capsule())

                    Text("archived \(relativeDate(entry.archivedAt))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)

                    if entry.messageCount > 0 {
                        Text("· \(entry.messageCount) msgs")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    Task {
                        await appState.restoreArchivedSession(entry)
                        reload()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                        Text("restore")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Move back to \(entry.originalProjectName)")

                Button {
                    pendingDelete = entry
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.errorTint)
                        .frame(width: 24, height: 22)
                        .background(Theme.errorTint.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.errorTint.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Permanently delete")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Theme.textFaint)
            Text("Archive is empty")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("Right-click any session → Archive to move it here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func reload() {
        entries = appState.archiveService.listArchived()
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
