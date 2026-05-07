import SwiftUI

/// Sheet for choosing a target project to duplicate a session into.
struct MoveSessionView: View {
    @EnvironmentObject var appState: AppState
    let context: AppState.MoveSessionContext
    @Binding var isPresented: Bool
    @State private var query = ""

    private var candidates: [Project] {
        let all = appState.projects.filter { $0.id != context.sourceProject.id }
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) || $0.originalPath.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Source session summary
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text(context.session.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                Text(context.sourceProject.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Theme.surface.opacity(0.5))

            Divider()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Filter projects…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }
            .padding(.horizontal, 20).padding(.vertical, 8)

            Divider()

            // Candidates
            if candidates.isEmpty {
                VStack(spacing: 8) {
                    Text("No other projects match")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(candidates) { project in
                            Button {
                                Task {
                                    await appState.copySessionToProject(
                                        session: context.session,
                                        sourceProject: context.sourceProject,
                                        target: project
                                    )
                                    isPresented = false
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.accent.opacity(0.7))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Theme.text)
                                        Text(project.originalPath)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text("\(project.sessions.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.textFaint)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.textFaint)
                                }
                                .padding(.horizontal, 20).padding(.vertical, 9)
                                .background(Theme.surface.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("The source session will stay in \(context.sourceProject.name). A copy will be created.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 520, height: 480)
        .background(Theme.surface)
    }

    private var header: some View {
        HStack {
            Text("Copy to Project")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}
