import SwiftUI
import AppKit

/// Settings panel for the in-app MCP server. Lets the user enable/disable,
/// pick a port, and copy the JSON snippet they need to drop into Claude
/// Code's `~/.claude/settings.json` (or any other MCP client's config).
struct MCPSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var portText: String = ""
    @State private var copied: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                enableToggle
                Divider()
                portSection
                Divider()
                snippetSection
                Divider()
                toolsList
                Spacer()
            }
            .padding()
        }
        .onAppear {
            portText = String(appState.mcpServerPort)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP server")
                    .font(.system(size: 14, weight: .semibold))
                Text("Lets Claude Code (or any MCP client) drive Claude Sessions: open conversations, extract dialogue, archive sessions, etc. Localhost only.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Enable toggle

    private var enableToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { appState.mcpServerEnabled },
                set: { appState.setMCPEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enable MCP server")
                        .font(.system(size: 12, weight: .medium))
                    Text(statusLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var statusLabel: String {
        if appState.mcpServerEnabled {
            return "Running on http://127.0.0.1:\(appState.mcpServerPort)/mcp"
        }
        return "Stopped"
    }

    private var statusColor: Color {
        appState.mcpServerEnabled ? .green : .secondary
    }

    // MARK: - Port

    private var portSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("Port",
                                  subtitle: "Default 7531. Bound to 127.0.0.1 only — no other host on your network can reach it. Changing the port restarts the server if it's running.")
            HStack(spacing: 8) {
                TextField("7531", text: $portText)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { applyPort() }
                    .controlSize(.small)
                    .disabled(!portChanged)
                Spacer()
            }
        }
    }

    private var portChanged: Bool {
        portText != String(appState.mcpServerPort)
    }

    private func applyPort() {
        guard let n = Int(portText), n > 1024, n < 65536 else { return }
        appState.mcpServerPort = n
        appState.restartMCPServer()
    }

    // MARK: - Snippet

    private var snippetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("Connect from Claude Code",
                                  subtitle: "Add this entry to `mcpServers` in Claude Code's settings:")

            Text(snippetText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

            HStack {
                Button(copied ? "Copied" : "Copy snippet") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippetText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .controlSize(.small)
                Spacer()
                Text("→ ~/.claude/settings.json")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var snippetText: String {
        """
        "claude-sessions": {
          "type": "http",
          "url": "http://127.0.0.1:\(appState.mcpServerPort)/mcp"
        }
        """
    }

    // MARK: - Tools list

    private var toolsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsSectionHeader("Exposed tools",
                                  subtitle: "delete_to_trash and the launch tools spawn UI side-effects. MCP clients should confirm with the user before invoking them.")
            Text("Navigation: list_projects, list_sessions, open_session, close_session\nRead: read_session_metadata, read_dialogue_only, read_full_transcript\nOrganize: star, unstar, hide, unhide, archive, unarchive, move_to_project, delete_to_trash\nLaunch: extract_and_open, resume_in_terminal")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
