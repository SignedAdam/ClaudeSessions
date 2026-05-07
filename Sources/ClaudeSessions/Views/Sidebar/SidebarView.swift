import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hiddenStore: HiddenStore
    @EnvironmentObject var favoritesStore: FavoritesStore
    @State private var expandedProjects: Set<String> = []
    @State private var favoritesExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField("search...", text: $appState.sidebarSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                if !appState.sidebarSearchText.isEmpty {
                    Button { appState.sidebarSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.surface2.opacity(0.3))

            // Projects & sessions
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Favorites section — only shown when at least one session is starred
                    if !favoritedSessions.isEmpty {
                        FavoritesSection(
                            sessions: favoritedSessions,
                            isExpanded: favoritesExpanded,
                            selectedSessionId: appState.selectedSessionId,
                            isDirty: appState.isDirty,
                            hiddenSessionIds: hiddenStore.hiddenSessionIds,
                            favoriteIds: favoritesStore.favoriteSessionIds,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    favoritesExpanded.toggle()
                                }
                            },
                            onSelectSession: { session in
                                Task { await appState.selectSession(session) }
                            },
                            onToggleFavorite: { session in
                                favoritesStore.toggle(session.id)
                            },
                            onToggleSessionHidden: { session in
                                hiddenStore.toggleSessionHidden(session.id)
                            },
                            onArchiveSession: { session in
                                Task { await appState.archiveSession(session) }
                            },
                            onMoveSession: { session in
                                appState.beginMoveSession(session)
                            },
                            onDeleteSession: { session in
                                appState.requestDeleteSession(session)
                            },
                            onShowVersions: { session in
                                appState.presentVersions(for: session)
                            }
                        )
                    }

                    if appState.projects.isEmpty && !appState.isLoading {
                        emptyState
                    } else {
                        ForEach(visibleProjects) { project in
                            ProjectSection(
                                project: project,
                                sessions: visibleSessions(for: project),
                                isExpanded: expandedProjects.contains(project.id),
                                selectedSessionId: appState.selectedSessionId,
                                isDirty: appState.isDirty,
                                isProjectHidden: hiddenStore.isProjectHidden(project.id),
                                hiddenSessionIds: hiddenStore.hiddenSessionIds,
                                favoriteIds: favoritesStore.favoriteSessionIds,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        if expandedProjects.contains(project.id) {
                                            expandedProjects.remove(project.id)
                                        } else {
                                            expandedProjects.insert(project.id)
                                        }
                                    }
                                },
                                onSelectSession: { session in
                                    Task { await appState.selectSession(session) }
                                },
                                onToggleProjectHidden: {
                                    hiddenStore.toggleProjectHidden(project.id)
                                },
                                onToggleSessionHidden: { session in
                                    hiddenStore.toggleSessionHidden(session.id)
                                },
                                onToggleSessionFavorite: { session in
                                    favoritesStore.toggle(session.id)
                                },
                                onArchiveSession: { session in
                                    Task { await appState.archiveSession(session) }
                                },
                                onMoveSession: { session in
                                    appState.beginMoveSession(session)
                                },
                                onDeleteSession: { session in
                                    appState.requestDeleteSession(session)
                                },
                                onShowVersions: { session in
                                    appState.presentVersions(for: session)
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            SidebarFooter()
        }
        .background(Theme.sidebarBg)
        .onChange(of: appState.projects) { _, newProjects in
            if expandedProjects.isEmpty, let first = newProjects.first {
                expandedProjects.insert(first.id)
            }
        }
        .onChange(of: appState.selectedSessionId) { _, newId in
            // When a session is opened from anywhere (dashboard, search, etc.),
            // make sure its containing project is expanded so the user sees it
            // highlighted in the sidebar.
            guard let id = newId else { return }
            for project in appState.projects {
                if project.sessions.contains(where: { $0.id == id }) {
                    expandedProjects.insert(project.id)
                    break
                }
            }
        }
    }

    // MARK: - Favorites

    /// All starred sessions from all projects, flat, sorted newest-first.
    /// Respects hidden + search filtering like everything else.
    private var favoritedSessions: [(SessionInfo, Project)] {
        let query = appState.sidebarSearchText.lowercased()
        let favIds = favoritesStore.favoriteSessionIds

        var out: [(SessionInfo, Project)] = []
        for project in appState.projects {
            // Respect project-level hidden unless showHidden
            if hiddenStore.isProjectHidden(project.id) && !hiddenStore.showHidden { continue }
            for session in project.sessions where favIds.contains(session.id) {
                if hiddenStore.isSessionHidden(session.id) && !hiddenStore.showHidden { continue }
                if !query.isEmpty {
                    let matches = session.title.lowercased().contains(query) ||
                        (session.firstPrompt?.lowercased().contains(query) ?? false) ||
                        project.name.lowercased().contains(query)
                    if !matches { continue }
                }
                out.append((session, project))
            }
        }
        out.sort { $0.0.modified > $1.0.modified }
        return out
    }

    // MARK: - Filtering pipeline
    // 1. Hidden filter — skip hidden projects/sessions unless showHidden is on
    // 2. Search filter — only items matching the query string
    // Each stage produces a reduced list used by the stage after.

    private var visibleProjects: [Project] {
        let query = appState.sidebarSearchText.lowercased()

        return appState.projects.compactMap { project in
            // Skip fully-hidden projects unless user is viewing hidden
            if hiddenStore.isProjectHidden(project.id) && !hiddenStore.showHidden {
                return nil
            }

            let sessions = visibleSessions(for: project)

            // If a search query is active, omit projects that have no matching sessions
            if !query.isEmpty {
                let nameMatches = project.name.lowercased().contains(query)
                if !nameMatches && sessions.isEmpty { return nil }
            } else if sessions.isEmpty {
                // No sessions after visibility filter — still show the folder though
                // so user sees the project exists. Only omit if filtered empty by search.
            }

            return project
        }
    }

    private func visibleSessions(for project: Project) -> [SessionInfo] {
        let query = appState.sidebarSearchText.lowercased()

        return project.sessions.filter { session in
            // Hidden filter
            if hiddenStore.isSessionHidden(session.id) && !hiddenStore.showHidden {
                return false
            }
            // Search filter
            if query.isEmpty { return true }
            return session.title.lowercased().contains(query) ||
                   (session.firstPrompt?.lowercased().contains(query) ?? false) ||
                   project.name.lowercased().contains(query)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("no sessions found")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Text("~/.claude/projects/")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Favorites section

struct FavoritesSection: View {
    let sessions: [(SessionInfo, Project)]
    let isExpanded: Bool
    let selectedSessionId: String?
    let isDirty: Bool
    let hiddenSessionIds: Set<String>
    let favoriteIds: Set<String>
    let onToggleExpand: () -> Void
    let onSelectSession: (SessionInfo) -> Void
    let onToggleFavorite: (SessionInfo) -> Void
    let onToggleSessionHidden: (SessionInfo) -> Void
    let onArchiveSession: (SessionInfo) -> Void
    let onMoveSession: (SessionInfo) -> Void
    let onDeleteSession: (SessionInfo) -> Void
    let onShowVersions: (SessionInfo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12)
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.warnTint)
                    Text("favorites")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(sessions.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(sessions, id: \.0.id) { session, project in
                        SessionRow(
                            session: session,
                            isSelected: session.id == selectedSessionId,
                            isDirty: isDirty && session.id == selectedSessionId,
                            isHidden: hiddenSessionIds.contains(session.id),
                            isFavorite: true,
                            showProjectHint: project.name,
                            onSelect: { onSelectSession(session) },
                            onToggleHidden: { onToggleSessionHidden(session) },
                            onToggleFavorite: { onToggleFavorite(session) },
                            onArchive: { onArchiveSession(session) },
                            onMoveToProject: { onMoveSession(session) },
                            onDelete: { onDeleteSession(session) },
                            onShowVersions: { onShowVersions(session) }
                        )
                    }
                }
            }

            // Subtle divider separating favorites from the project tree
            Rectangle()
                .fill(Theme.border.opacity(0.25))
                .frame(height: 1)
                .padding(.top, 4)
        }
    }
}

// MARK: - Project section

struct ProjectSection: View {
    let project: Project
    let sessions: [SessionInfo]
    let isExpanded: Bool
    let selectedSessionId: String?
    let isDirty: Bool
    let isProjectHidden: Bool
    let hiddenSessionIds: Set<String>
    let favoriteIds: Set<String>
    let onToggleExpand: () -> Void
    let onSelectSession: (SessionInfo) -> Void
    let onToggleProjectHidden: () -> Void
    let onToggleSessionHidden: (SessionInfo) -> Void
    let onToggleSessionFavorite: (SessionInfo) -> Void
    let onArchiveSession: (SessionInfo) -> Void
    let onMoveSession: (SessionInfo) -> Void
    let onDeleteSession: (SessionInfo) -> Void
    let onShowVersions: (SessionInfo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12)
                    Text(project.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .italic(isProjectHidden)
                        .lineLimit(1)
                    if isProjectHidden {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Text("\(sessions.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
                .opacity(isProjectHidden ? 0.55 : 1)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(isProjectHidden ? "Unhide Project" : "Hide Project",
                       action: onToggleProjectHidden)
            }

            // LazyVStack so projects with hundreds of sessions don't
            // materialize every row at once when expanded.
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: session.id == selectedSessionId,
                            isDirty: isDirty && session.id == selectedSessionId,
                            isHidden: hiddenSessionIds.contains(session.id),
                            isFavorite: favoriteIds.contains(session.id),
                            onSelect: { onSelectSession(session) },
                            onToggleHidden: { onToggleSessionHidden(session) },
                            onToggleFavorite: { onToggleSessionFavorite(session) },
                            onArchive: { onArchiveSession(session) },
                            onMoveToProject: { onMoveSession(session) },
                            onDelete: { onDeleteSession(session) },
                            onShowVersions: { onShowVersions(session) }
                        )

                        // Indented subagent rows that ran under this session
                        ForEach(session.subagents) { sub in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Theme.border.opacity(0.5))
                                    .frame(width: 1)
                                    .padding(.leading, 22)
                                SessionRow(
                                    session: sub,
                                    isSelected: sub.id == selectedSessionId,
                                    isDirty: false,
                                    isHidden: hiddenSessionIds.contains(sub.id),
                                    isFavorite: favoriteIds.contains(sub.id),
                                    onSelect: { onSelectSession(sub) },
                                    onToggleHidden: { onToggleSessionHidden(sub) },
                                    onToggleFavorite: { onToggleSessionFavorite(sub) },
                                    onArchive: { onArchiveSession(sub) },
                                    onMoveToProject: { onMoveSession(sub) },
                                    onDelete: { onDeleteSession(sub) },
                                    onShowVersions: { onShowVersions(sub) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar footer

struct SidebarFooter: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hiddenStore: HiddenStore
    @State private var refreshing = false

    private var stats: (projects: Int, sessions: Int) {
        let sessions = appState.projects.reduce(0) { $0 + $1.sessions.count }
        return (appState.projects.count, sessions)
    }

    private var archivedCount: Int {
        appState.archiveService.listArchived().count
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)

            HStack(spacing: 4) {
                // All icon-only so the row stays compact even in a narrow sidebar.
                // Tooltips carry the labels.
                FooterIconButton(
                    icon: "arrow.clockwise",
                    tooltip: "Refresh — rescan ~/.claude/projects/",
                    spinning: refreshing
                ) {
                    refreshing = true
                    Task {
                        await appState.loadProjects()
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        refreshing = false
                    }
                }

                FooterIconButton(icon: "archivebox", tooltip: "Archive") {
                    appState.showArchiveSheet = true
                }

                FooterIconButton(icon: "tray.full", tooltip: "Backup Vault — restore deleted conversations") {
                    appState.showBackupVaultSheet = true
                }

                FooterIconButton(
                    icon: hiddenStore.showHidden ? "eye" : "eye.slash",
                    tooltip: hiddenStore.showHidden ? "Hide hidden items" : "Show hidden items"
                ) {
                    hiddenStore.showHidden.toggle()
                }

                Spacer()

                // Compact inline stats. Icons are inlined with the text via
                // SwiftUI's Image-in-Text interpolation — guaranteed single
                // line at any width, same baseline throughout.
                (
                    Text(Image(systemName: "folder")).foregroundStyle(Theme.textSecondary) +
                    Text(" \(stats.projects)").foregroundStyle(Theme.text) +
                    Text("  ·  ").foregroundStyle(Theme.textTertiary) +
                    Text(Image(systemName: "bubble.left")).foregroundStyle(Theme.textSecondary) +
                    Text(" \(stats.sessions)").foregroundStyle(Theme.text)
                )
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.surface2.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .help("\(stats.projects) projects, \(stats.sessions) sessions")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.surface.opacity(0.5))
        }
    }
}

private struct FooterIconButton: View {
    let icon: String
    let tooltip: String
    var spinning: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? Theme.accent : Theme.textSecondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                    value: spinning
                )
                .frame(width: 26, height: 22)
                .background(hovered ? Theme.surface2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.border.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in hovered = h }
        .help(tooltip)
    }
}
