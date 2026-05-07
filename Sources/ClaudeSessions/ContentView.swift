import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeStore: ThemeStore

    @State private var showThemePicker = false

    /// Show the first-run onboarding wizard once. Persists across launches
    /// via UserDefaults["didShowOnboarding"].
    @AppStorage("didShowOnboarding") private var didShowOnboarding: Bool = false
    @State private var presentOnboarding: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.background
                .ignoresSafeArea()

            if themeStore.wavyBackgroundEnabled {
                WavyBackground()
            }

            VStack(spacing: 0) {
                TopBarView(showThemePicker: $showThemePicker)
                    // Extend into the titlebar region so our icons sit at the
                    // same y as the native traffic lights.
                    .padding(.top, 0)

                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 420)
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    Group {
                        if appState.isLoading && appState.currentConversation == nil {
                            loadingView
                        } else if let conversation = appState.currentConversation {
                            ConversationContainerView(conversation: conversation)
                        } else {
                            HomeDashboardView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                }
                .navigationTitle("")
                // IMPORTANT: do NOT add `.toolbar(.hidden, for: .windowToolbar)` here.
                // That modifier kills the entire titlebar, including traffic lights.
                // With .windowStyle(.hiddenTitleBar) on the WindowGroup, the title text
                // is already hidden but traffic lights remain — they'll naturally
                // overlay our TopBarView in the top-left region.

                // Global bottom bar — always visible. Hosts theme/settings
                // on the far right, and conversation metrics on the left
                // when a conversation is open.
                BottomBarView(showThemePicker: $showThemePicker)
            }
            // Extend the VStack under the titlebar area so TopBarView starts
            // at y=0, aligning our right-side icons with the traffic lights.
            .ignoresSafeArea(edges: .top)

            if showThemePicker {
                themePickerOverlay
            }
        }
        // Force a full re-build of the tree whenever the palette changes.
        // Without this, views that don't observe ThemeStore directly stay
        // stuck on the old Theme.xxx values until their parent re-renders.
        .id(themeStore.current.id)
        .task {
            await appState.loadProjects()
            // First-launch wizard. Run once after the load so the app's
            // window is fully on screen before the modal appears.
            if !didShowOnboarding {
                presentOnboarding = true
            }
        }
        .sheet(isPresented: $presentOnboarding) {
            OnboardingView()
                .environmentObject(appState)
                .environmentObject(themeStore)
        }
        .sheet(isPresented: $appState.showSearchSheet) {
            SearchView(isPresented: $appState.showSearchSheet)
                .environmentObject(appState)
                .environmentObject(themeStore)
        }
        .sheet(isPresented: $appState.showArchiveSheet) {
            ArchiveView(isPresented: $appState.showArchiveSheet)
                .environmentObject(appState)
                .environmentObject(themeStore)
        }
        .sheet(isPresented: $appState.showBackupVaultSheet) {
            BackupVaultView(isPresented: $appState.showBackupVaultSheet)
                .environmentObject(appState)
                .environmentObject(themeStore)
        }
        .sheet(isPresented: $appState.showSubagentsSheet) {
            SubagentsView(isPresented: $appState.showSubagentsSheet)
                .environmentObject(appState)
                .environmentObject(themeStore)
        }
        .sheet(item: $appState.versionsContext) { ctx in
            VersionsView(
                sessionId: ctx.sessionId,
                projectSlug: ctx.projectSlug,
                projectCwd: ctx.projectCwd,
                sessionTitle: ctx.sessionTitle,
                isPresented: Binding(
                    get: { appState.versionsContext != nil },
                    set: { if !$0 { appState.versionsContext = nil } }
                )
            )
            .environmentObject(appState)
            .environmentObject(themeStore)
        }
        .alert(
            "Move this conversation to Trash?",
            isPresented: Binding(
                get: { appState.pendingDelete != nil },
                set: { if !$0 { appState.pendingDelete = nil } }
            ),
            presenting: appState.pendingDelete
        ) { session in
            Button("Move to Trash", role: .destructive) {
                Task { await appState.confirmDeleteSession(session) }
            }
            Button("Cancel", role: .cancel) {
                appState.pendingDelete = nil
            }
        } message: { session in
            Text("\(session.title)\n\nThe file will be moved to your macOS Trash. You can restore it from Trash until you empty it. This does not affect any edits you're currently making to other conversations.")
        }
        .sheet(item: $appState.moveSessionContext) { ctx in
            MoveSessionView(
                context: ctx,
                isPresented: Binding(
                    get: { appState.moveSessionContext != nil },
                    set: { if !$0 { appState.moveSessionContext = nil } }
                )
            )
            .environmentObject(appState)
            .environmentObject(themeStore)
        }
    }

    private var themePickerOverlay: some View {
        ZStack(alignment: .topTrailing) {
            // Use a theme-aware dimming overlay so it reads correctly in Vellum
            (Theme.isLight ? Color.black.opacity(0.08) : Color.black.opacity(0.12))
                .ignoresSafeArea()
                .onTapGesture { showThemePicker = false }

            ThemePickerView(isPresented: $showThemePicker)
                .environmentObject(themeStore)
                .padding(.top, 38)
                .padding(.trailing, 10)
                .transition(.scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showThemePicker)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.accent)
            Text("Loading conversation…")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
