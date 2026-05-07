import SwiftUI

/// Cross-project subagent browser. Lists every subagent run that the
/// scanner stitched into `Project.sessions[i].subagents`, filterable by
/// title, parent title, project name, or agent name. Click a row to open
/// that subagent in the conversation pane.
struct SubagentsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query: String = ""

    private var entries: [SubagentIndexEntry] {
        SubagentIndex.build(from: appState.projects)
    }

    private var filtered: [SubagentIndexEntry] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter { e in
            e.subagent.title.lowercased().contains(q)
            || e.parent.title.lowercased().contains(q)
            || e.project.name.lowercased().contains(q)
            || (e.agentName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar

            Divider()

            if entries.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                noMatchState
            } else {
                list
            }
        }
        .frame(width: 640, height: 560)
        .background(Theme.surface)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.toolTint)
                Text("Subagents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.toolTint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.toolTint.opacity(0.14))
                    .clipShape(Capsule())
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            TextField("filter subagents…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filtered) { entry in
                    Button {
                        Task { await appState.selectSession(entry.subagent) }
                        isPresented = false
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func row(_ entry: SubagentIndexEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.toolTint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let name = entry.agentName {
                        Text(name)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.toolTint)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.toolTint.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Text(entry.subagent.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.project.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Text("·").foregroundStyle(Theme.textFaint)
                    Text(entry.parent.title)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Theme.textFaint)
                    Text(DateFormatting.dateString(entry.subagent.modified))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.border.opacity(0.4), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("No subagent runs yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("When Claude Code spins up a subagent — for code review, search, planning — its transcript lands in `<project>/<sessionId>/subagents/`. You'll see them all here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noMatchState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text("No matches for \"\(query)\"")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
