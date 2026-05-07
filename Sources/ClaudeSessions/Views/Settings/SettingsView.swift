import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ExtractSettingsView()
                .tabItem { Label("Extract", systemImage: "sparkles") }

            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }

            ClaudeCodeSettingsView()
                .tabItem { Label("Claude Code", systemImage: "gearshape.2") }

            MCPSettingsView()
                .tabItem { Label("MCP", systemImage: "antenna.radiowaves.left.and.right") }

            AISearchSettingsView()
                .tabItem { Label("AI Search", systemImage: "magnifyingglass") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench") }
        }
        .frame(minWidth: 520, idealWidth: 640, maxWidth: 900,
               minHeight: 420, idealHeight: 520, maxHeight: 900)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("displayName") private var displayName = "You"
    @AppStorage("theme") private var theme = "system"
    @EnvironmentObject var hiddenStore: HiddenStore
    @EnvironmentObject var themeStore: ThemeStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                identitySection
                Divider()
                terminalSection
                Divider()
                visibilitySection
                Divider()
                appearanceSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("Identity",
                                  subtitle: "Shown in message headers for your messages.")
            HStack(spacing: 8) {
                Text("Display name:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("You", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("Terminal",
                                  subtitle: "Resume / Extract / Open-in-CLI write a tiny `.command` script and let macOS open it.")
            Text("By default that's Terminal.app. To use a different terminal, right-click any `.command` file in Finder → Open With → Other → choose your terminal → check \"Always Open With\". From then on, every launch from this app opens there.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("Visibility",
                                  subtitle: "Hidden items are visual-only. The files stay in place; the user can re-show with the eye-slash toggle in the sidebar footer.")
            Toggle(isOn: $hiddenStore.showHidden) {
                Text("Show hidden conversations")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            if !hiddenStore.hiddenSessionIds.isEmpty || !hiddenStore.hiddenProjectIds.isEmpty {
                Text("\(hiddenStore.hiddenSessionIds.count) hidden session\(hiddenStore.hiddenSessionIds.count == 1 ? "" : "s"), \(hiddenStore.hiddenProjectIds.count) hidden project\(hiddenStore.hiddenProjectIds.count == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("Appearance",
                                  subtitle: "For palette and ambient-field options, use the paintpalette icon in the bottom bar.")
            HStack(spacing: 8) {
                Text("System theme:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Picker("", selection: $theme) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                Spacer()
            }
        }
    }
}

/// Shared section header used across settings panels.
struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ExtractSettingsView: View {
    @AppStorage("extractMode") private var extractModeRaw: String = ExtractMode.newSession.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Extract Mode")
                .font(.system(size: 13, weight: .semibold))

            Text("When you click the Extract button, Claude Sessions strips tool calls, tool results, and system messages — leaving only the human↔Claude dialogue — and opens it in Claude Code.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                RadioOption(
                    title: "New resumable session",
                    subtitle: "Write a clean JSONL file into the same project and open with `claude --resume`. The new session appears in Claude Code's own resume picker. The original session is untouched.",
                    isSelected: extractModeRaw == ExtractMode.newSession.rawValue,
                    recommended: true
                ) {
                    extractModeRaw = ExtractMode.newSession.rawValue
                }

                RadioOption(
                    title: "Piped prompt (fresh context)",
                    subtitle: "Pipe the cleaned dialogue into a brand new `claude` session as its first prompt. Faster, no on-disk session file, but Claude Code starts completely fresh.",
                    isSelected: extractModeRaw == ExtractMode.pipedPrompt.rawValue,
                    recommended: false
                ) {
                    extractModeRaw = ExtractMode.pipedPrompt.rawValue
                }
            }

            Spacer()

            Text("You can override per-click by right-clicking the Extract button.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RadioOption: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                        if recommended {
                            Text("recommended")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AISearchSettingsView: View {
    @AppStorage("openRouterModel") private var model = "anthropic/claude-sonnet-4"
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader("OpenRouter",
                                      subtitle: "AI Search routes prompts via OpenRouter. Only conversation titles and first messages are sent — full conversation content is never transmitted.")
                HStack(spacing: 8) {
                    Text("API key:")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    SecureField("sk-or-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { apiKey = KeychainService.load() ?? "" }
                        .onChange(of: apiKey) { _, newValue in
                            if newValue.isEmpty { KeychainService.delete() }
                            else { try? KeychainService.save(key: newValue) }
                        }
                    Spacer()
                }
                Divider()
                HStack(spacing: 8) {
                    Text("Model:")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $model) {
                        Text("Claude Sonnet 4").tag("anthropic/claude-sonnet-4")
                        Text("Claude Haiku 4.5").tag("anthropic/claude-haiku-4-5")
                        Text("Gemini 2.5 Flash").tag("google/gemini-2.5-flash")
                        Text("GPT-4o Mini").tag("openai/gpt-4o-mini")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    Spacer()
                }
                Text("Stored in your macOS Keychain — never written to disk in plaintext.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("cliPath") private var cliPath = "/usr/local/bin/claude"
    @AppStorage("backupDir") private var backupDir = "~/.claude-sessions-backups"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader("Paths",
                                      subtitle: "Power-user overrides. The defaults are correct for nearly everyone.")
                pathRow(label: "Claude CLI:", binding: $cliPath, placeholder: "/usr/local/bin/claude")
                pathRow(label: "Backup directory:", binding: $backupDir, placeholder: "~/.claude-sessions-backups")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func pathRow(label: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 110, alignment: .trailing)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}
