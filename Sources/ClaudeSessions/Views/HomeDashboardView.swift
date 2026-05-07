import SwiftUI

/// The landing view when no conversation is selected.
/// Designed to be useful, not decorative — shows recent activity,
/// quick actions, and stats about your Claude Code usage.
struct HomeDashboardView: View {
    @EnvironmentObject var appState: AppState

    private var allSessions: [(session: SessionInfo, project: Project)] {
        appState.projects.flatMap { p in p.sessions.map { ($0, p) } }
    }

    private var recentSessions: [(session: SessionInfo, project: Project)] {
        allSessions.sorted { $0.session.modified > $1.session.modified }.prefix(8).map { $0 }
    }

    private var topProjects: [(project: Project, count: Int)] {
        appState.projects
            .map { ($0, $0.sessions.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map { $0 }
    }

    private var totalSessions: Int {
        appState.projects.reduce(0) { $0 + $1.sessions.count }
    }

    private var totalMessages: Int {
        allSessions.reduce(0) { $0 + $1.session.messageCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                quickActions
                if !recentSessions.isEmpty {
                    recentSessionsSection
                }
                HStack(alignment: .top, spacing: 20) {
                    if !topProjects.isEmpty {
                        topProjectsSection
                    }
                    statsSection
                }
                tipsSection
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 60)
            .frame(maxWidth: 1080)
            // Center the content block within the ScrollView — no more
            // huge empty space on the right.
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                Text("Claude Sessions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            Text(greetingLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greet: String
        switch hour {
        case 5..<12:  greet = "Good morning"
        case 12..<17: greet = "Good afternoon"
        case 17..<22: greet = "Good evening"
        default:      greet = "Late night hacking"
        }
        if totalSessions == 0 {
            return "\(greet) — no sessions found yet"
        }
        return "\(greet) — \(totalSessions) sessions across \(appState.projects.count) projects"
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickActionCard(
                icon: "arrow.uturn.forward",
                title: "Continue last",
                subtitle: recentSessions.first.map { $0.session.title } ?? "No recent",
                accent: Theme.humanTint,
                enabled: recentSessions.first != nil
            ) {
                if let first = recentSessions.first {
                    Task { await appState.selectSession(first.session) }
                }
            }

            QuickActionCard(
                icon: "magnifyingglass",
                title: "Search",
                subtitle: "Find any conversation · ⌘⇧F",
                accent: Theme.accent,
                enabled: totalSessions > 0
            ) {
                appState.showSearchSheet = true
            }

            QuickActionCard(
                icon: "shuffle",
                title: "Random session",
                subtitle: "Rediscover something old",
                accent: Theme.toolTint,
                enabled: totalSessions > 0
            ) {
                if let random = allSessions.randomElement() {
                    Task { await appState.selectSession(random.session) }
                }
            }
        }
    }

    // MARK: - Recent sessions

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recent")

            VStack(spacing: 4) {
                ForEach(recentSessions, id: \.session.id) { pair in
                    Button {
                        Task { await appState.selectSession(pair.session) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.session.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(pair.project.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                    Text("·").foregroundStyle(Theme.textFaint)
                                    Text(DateFormatting.dateString(pair.session.modified))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                    if pair.session.messageCount > 0 {
                                        Text("·").foregroundStyle(Theme.textFaint)
                                        Text("\(pair.session.messageCount) msgs")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.textFaint)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border.opacity(0.3), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Top projects

    private var topProjectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Busiest projects")

            VStack(spacing: 4) {
                ForEach(topProjects, id: \.project.id) { item in
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent.opacity(0.5))
                        Text(item.project.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border.opacity(0.25), lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("At a glance")

            VStack(spacing: 4) {
                statRow("Sessions", value: "\(totalSessions)")
                statRow("Projects", value: "\(appState.projects.count)")
                statRow("Messages", value: formatNumber(totalMessages))
                statRow("Oldest", value: oldestDate)
                statRow("Latest", value: latestDate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border.opacity(0.25), lineWidth: 1))
    }

    private var oldestDate: String {
        guard let d = allSessions.map(\.session.created).min() else { return "—" }
        return DateFormatting.dateString(d)
    }

    private var latestDate: String {
        guard let d = allSessions.map(\.session.modified).max() else { return "—" }
        return DateFormatting.dateString(d)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("What you can do here")

            VStack(spacing: 6) {
                TipRow(icon: "sparkles", text: "Extract clean dialogue from any session and open it as a fresh Claude Code session — no tool call noise.")
                TipRow(icon: "pencil", text: "Edit any message in-place. Original files are backed up before every save.")
                TipRow(icon: "magnifyingglass", text: "Search by keyword, or use AI Search (requires OpenRouter key) to find conversations by meaning.")
                TipRow(icon: "terminal", text: "Resume any session directly in iTerm2 or Terminal.")
            }
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Components

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let enabled: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(hovered && enabled ? Theme.surfaceRaised : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hovered && enabled ? accent.opacity(0.4) : Theme.border.opacity(0.3), lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }
}

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
