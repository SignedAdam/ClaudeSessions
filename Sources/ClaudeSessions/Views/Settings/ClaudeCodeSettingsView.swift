import SwiftUI
import AppKit

/// Surfaces Claude Code's own settings (the ones that live in
/// `~/.claude/settings.json`) so the user doesn't have to hunt for them
/// in a JSON file. We show the most impactful keys with proper controls
/// and offer a "reveal in Finder" for everything else.
///
/// See: https://docs.claude.com/en/docs/claude-code/settings
struct ClaudeCodeSettingsView: View {
    @StateObject private var store = ClaudeCodeConfigStore()
    @AppStorage("embeddedChatEnabled") private var embeddedChatEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                embeddedChatSection
                Divider()
                cleanupSection
                Divider()
                modelSection
                Divider()
                telemetrySection
                Divider()
                rawAccessSection
                if let err = store.lastError { errorRow(err) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { store.load() }
    }

    // MARK: - Embedded chat

    private var embeddedChatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Embedded chat",
                          subtitle: "When enabled, an inline composer at the bottom of every conversation lets you reply via `claude -p --resume`. Disable to keep all interactive work in your terminal.")
            Toggle(isOn: $embeddedChatEnabled) {
                Text("Show composer on conversation view")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code")
                    .font(.system(size: 14, weight: .semibold))
                Text("Settings stored in ~/.claude/settings.json. Affects every Claude Code session — not just this app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Session retention",
                          subtitle: "How long Claude Code keeps your transcripts before auto-deleting them.")
            HStack(spacing: 8) {
                Text("cleanupPeriodDays:")
                    .font(.system(size: 11, design: .monospaced))
                TextField("30", text: $store.cleanupPeriodDaysText)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Text("days").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Save") { store.applyCleanupDays() }
                    .controlSize(.small)
                    .disabled(!store.cleanupDirty)
            }
            Text("Default is 30. Set to a very large number (e.g. 36500) to effectively disable cleanup. Continuous Backup (in the Backup tab) protects against this regardless.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Default model",
                          subtitle: "Used when starting a new Claude Code session.")
            HStack(spacing: 8) {
                Text("model:")
                    .font(.system(size: 11, design: .monospaced))
                TextField("claude-sonnet-4-6 (or empty for default)", text: $store.modelText)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { store.applyModel() }
                    .controlSize(.small)
                    .disabled(!store.modelDirty)
            }
            Text("Examples: claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5. Leave empty to use Anthropic's default.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Telemetry

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Telemetry",
                          subtitle: "Whether Claude Code reports anonymous usage data to Anthropic.")
            Toggle(isOn: $store.disableTelemetry) {
                Text("Disable telemetry")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .onChange(of: store.disableTelemetry) { _, _ in store.applyTelemetry() }
        }
    }

    // MARK: - Raw access

    private var rawAccessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("All other settings",
                          subtitle: "Permissions, custom statuslines, hooks, env vars, MCP servers, etc.")
            HStack(spacing: 8) {
                Button("Open settings.json") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: store.settingsPath))
                }
                .controlSize(.small)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(store.settingsPath,
                                                  inFileViewerRootedAtPath: "")
                }
                .controlSize(.small)
                Spacer()
                Text(store.settingsPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Bits

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func errorRow(_ err: String) -> some View {
        Text("Error: \(err)")
            .font(.system(size: 10))
            .foregroundStyle(.red)
    }
}

// MARK: - Backing store

/// Reads + writes ~/.claude/settings.json. Tries to be conservative:
/// loads as untyped JSON, edits the keys we know about, leaves everything
/// else untouched. Never reformats the file beyond what JSONSerialization
/// produces.
@MainActor
final class ClaudeCodeConfigStore: ObservableObject {
    @Published var cleanupPeriodDaysText: String = "30"
    @Published var modelText: String = ""
    @Published var disableTelemetry: Bool = false
    @Published private(set) var lastError: String?

    private var loadedDays: String = "30"
    private var loadedModel: String = ""
    private var rawConfig: [String: Any] = [:]

    let settingsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/settings.json"
    }()

    var cleanupDirty: Bool { cleanupPeriodDaysText != loadedDays }
    var modelDirty: Bool { modelText != loadedModel }

    func load() {
        lastError = nil
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath),
              let data = fm.contents(atPath: settingsPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // No settings file or unparseable — start blank
            rawConfig = [:]
            return
        }
        rawConfig = dict

        if let v = dict["cleanupPeriodDays"] as? Int {
            cleanupPeriodDaysText = String(v)
        } else if let v = dict["cleanupPeriodDays"] as? String {
            cleanupPeriodDaysText = v
        }
        loadedDays = cleanupPeriodDaysText

        if let v = dict["model"] as? String {
            modelText = v
        }
        loadedModel = modelText

        // Telemetry: Claude Code's official key is `disableTelemetry: true`.
        // Some users use environment variables instead; those won't show here.
        disableTelemetry = (dict["disableTelemetry"] as? Bool) ?? false
    }

    func applyCleanupDays() {
        guard let n = Int(cleanupPeriodDaysText), n >= 0 else {
            lastError = "cleanupPeriodDays must be a non-negative integer"
            return
        }
        rawConfig["cleanupPeriodDays"] = n
        save()
        loadedDays = cleanupPeriodDaysText
    }

    func applyModel() {
        let trimmed = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            rawConfig.removeValue(forKey: "model")
        } else {
            rawConfig["model"] = trimmed
        }
        save()
        loadedModel = modelText
    }

    func applyTelemetry() {
        rawConfig["disableTelemetry"] = disableTelemetry
        save()
    }

    private func save() {
        lastError = nil
        do {
            let data = try JSONSerialization.data(withJSONObject: rawConfig,
                                                  options: [.prettyPrinted, .sortedKeys])
            // Ensure the parent dir exists (in case ~/.claude/ is missing)
            let dir = (settingsPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: settingsPath))
        } catch {
            lastError = error.localizedDescription
        }
    }
}
