import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var isAISearch = false
    @State private var isSearching = false
    @State private var results: [SessionInfo] = []
    @State private var errorMessage: String?

    private let aiSearch = AISearchService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Search Conversations")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search conversations...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { performSearch() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            // Mode toggle
            HStack(spacing: 16) {
                Toggle("Text Search", isOn: .constant(!isAISearch))
                    .toggleStyle(.radioToggle(color: Theme.humanTint))
                    .onTapGesture { isAISearch = false }

                Toggle("AI Search", isOn: .constant(isAISearch))
                    .toggleStyle(.radioToggle(color: Theme.accent))
                    .onTapGesture { isAISearch = true }

                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider()

            // Results
            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching with AI...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.errorTint)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
            } else if results.isEmpty && !query.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    Text("No conversations match your query.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { session in
                            Button {
                                Task { await appState.selectSession(session) }
                                isPresented = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(2)
                                        HStack(spacing: 6) {
                                            Text(DateFormatting.dateString(session.modified))
                                                .font(.system(size: 11))
                                            if session.messageCount > 0 {
                                                Text("\(session.messageCount) msgs")
                                                    .font(.system(size: 10))
                                            }
                                        }
                                        .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.surface2.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 500, height: 450)
        .background(Theme.surface)
        .onChange(of: query) { _, _ in
            if !isAISearch {
                performTextSearch()
            }
        }
    }

    private func performSearch() {
        if isAISearch {
            performAISearch()
        } else {
            performTextSearch()
        }
    }

    private func performTextSearch() {
        let q = query.lowercased()
        guard !q.isEmpty else {
            results = []
            return
        }

        results = appState.projects.flatMap(\.sessions).filter { session in
            session.title.lowercased().contains(q) ||
            (session.firstPrompt?.lowercased().contains(q) ?? false)
        }.sorted { $0.modified > $1.modified }
    }

    private func performAISearch() {
        guard !query.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        let conversations = appState.projects.flatMap(\.sessions).map { session in
            let project = appState.projects.first { $0.sessions.contains { $0.id == session.id } }
            return (
                id: session.id,
                summary: session.title,
                firstPrompt: session.firstPrompt,
                project: project?.name ?? "",
                date: DateFormatting.dateString(session.modified)
            )
        }

        Task {
            do {
                let result = try await aiSearch.search(query: query, conversations: conversations)
                let allSessions = appState.projects.flatMap(\.sessions)
                results = result.sessionIds.compactMap { id in
                    allSessions.first { $0.id == id }
                }
                isSearching = false
            } catch {
                errorMessage = error.localizedDescription
                isSearching = false
            }
        }
    }
}

// MARK: - Radio Toggle Style

struct RadioToggleStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(configuration.isOn ? color : Color.clear)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .strokeBorder(configuration.isOn ? color : Theme.textSecondary, lineWidth: 1)
                )
            configuration.label
                .foregroundStyle(configuration.isOn ? Theme.text : Theme.textSecondary)
        }
    }
}

extension ToggleStyle where Self == RadioToggleStyle {
    static func radioToggle(color: Color) -> RadioToggleStyle {
        RadioToggleStyle(color: color)
    }
}
