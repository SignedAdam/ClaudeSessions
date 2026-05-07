import SwiftUI
import AppKit

/// Manages the list of filesystem roots scanned for Claude Code sessions.
/// The default `~/.claude/projects/` root is always included and cannot be
/// removed. Users can add extra roots — useful for archived sets, mounted
/// backups, or transcripts synced from a second machine.
struct ScanLocationsSettingsView: View {
    @EnvironmentObject var scanRootStore: ScanRootStore
    @State private var lastError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(
                    "Scan locations",
                    subtitle: "Folders Claude Sessions reads when listing projects and sessions. The default ~/.claude/projects/ is always included; add extras for archived sets, mounted backups, or a synced second machine."
                )

                rootRow(url: ScanRootStore.defaultRoot, isDefault: true)
                ForEach(scanRootStore.customRoots, id: \.path) { url in
                    rootRow(url: url, isDefault: false)
                }

                HStack(spacing: 8) {
                    Button {
                        showFolderPicker()
                    } label: {
                        Label("Add location…", systemImage: "plus")
                    }
                    if let err = lastError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.top, 4)

                Text("Adding a location only changes what the app *reads*. The continuous backup mirror still watches the default root only — pointing the app at a backup folder won't double-mirror it.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func rootRow(url: URL, isDefault: Bool) -> some View {
        let stats = stats(for: url)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDefault ? "house.fill" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(isDefault ? Theme.accent : Theme.textSecondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if isDefault {
                        Text("default")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(stats)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer()

            if !isDefault {
                Button {
                    scanRootStore.removeRoot(url)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Remove this scan location")
            }
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stats(for url: URL) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return "missing"
        }
        let entries = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        let projectDirs = entries.filter { name in
            guard !name.hasPrefix(".") else { return false }
            var isSub: ObjCBool = false
            return fm.fileExists(atPath: url.path + "/" + name, isDirectory: &isSub) && isSub.boolValue
        }
        return "\(projectDirs.count) project folder\(projectDirs.count == 1 ? "" : "s")"
    }

    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick a folder containing Claude Code project subfolders."
        panel.prompt = "Add"

        if panel.runModal() == .OK, let url = panel.url {
            lastError = scanRootStore.addRoot(url)
        }
    }
}
