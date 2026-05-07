import SwiftUI
import AppKit

// MARK: - NSApplicationDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Swift Package executables default to accessory activation —
        // no Dock icon, no Cmd+Tab. Force regular GUI.
        NSApp.setActivationPolicy(.regular)

        DockIconManager.applyFromDefaults()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ClaudeSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var themeStore = ThemeStore.shared
    @StateObject private var hiddenStore = HiddenStore.shared
    @StateObject private var favoritesStore = FavoritesStore.shared
    @StateObject private var scanRootStore = ScanRootStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(themeStore)
                .environmentObject(hiddenStore)
                .environmentObject(favoritesStore)
                .environmentObject(scanRootStore)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
                .background(WindowAccessor { window in
                    configureWindow(window)
                })
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") { Task { await appState.save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!appState.isDirty)
            }

            CommandGroup(after: .textEditing) {
                Button("Toggle JSON Mode") { appState.isJSONMode.toggle() }
                    .keyboardShortcut("j", modifiers: .command)
                Button("Toggle System Messages") { appState.showSystemMessages.toggle() }
                    .keyboardShortcut("y", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textFormatting) {
                Button("Search Conversations") { appState.showSearchSheet = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh Projects") { Task { await appState.loadProjects() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(themeStore)
                .environmentObject(hiddenStore)
                .environmentObject(favoritesStore)
                .environmentObject(scanRootStore)
        }
    }

    /// Configure the NSWindow. We keep the native titlebar area (transparent)
    /// so macOS traffic lights and toolbar items render in their usual spot,
    /// and the wavy background is free to extend behind them via .fullSizeContentView.
    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // Ensure traffic lights are visible
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}
