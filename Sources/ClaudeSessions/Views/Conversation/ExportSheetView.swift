import SwiftUI
import AppKit

/// Unified export UI. One sheet, four formats: Markdown, JSON, Codex CLI, Gemini CLI.
struct ExportSheetView: View {
    let conversation: Conversation
    let title: String
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var format: ExportService.Format = .markdown
    @State private var includeTools: Bool = true
    @State private var copied: Bool = false
    @State private var savedTo: String? = nil

    private var result: ExportService.Result {
        ExportService.export(
            format: format,
            conversation: conversation,
            title: title,
            includeTools: includeTools,
            displayName: appState.displayName,
            editedTexts: appState.editedTexts,
            deletedMessageIds: appState.deletedMessageIds
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formatPicker
            Divider()
            optionsBar
            Divider()
            previewPane
            Divider()
            actionsBar
        }
        .frame(width: 720, height: 580)
        .background(Theme.surface)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Export Conversation")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("· \(title)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Format picker (segmented)

    private var formatPicker: some View {
        HStack(spacing: 6) {
            ForEach(ExportService.Format.allCases) { f in
                FormatPill(
                    label: f.displayName,
                    icon: icon(for: f),
                    active: format == f
                ) {
                    format = f
                    copied = false
                    savedTo = nil
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func icon(for f: ExportService.Format) -> String {
        switch f {
        case .markdown: return "doc.richtext"
        case .json:     return "curlybraces"
        case .codex:    return "terminal"
        case .gemini:   return "sparkle"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .cursor:   return "cursorarrow.rays"
        }
    }

    // MARK: - Options

    private var optionsBar: some View {
        HStack(spacing: 14) {
            // Format-specific options
            if format.supportsToolToggle {
                Toggle(isOn: $includeTools) {
                    Text("Include tool calls")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Tool calls omitted — \(format.displayName) sessions are recreated as a clean dialogue.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()

            // Per-format hint
            formatHint
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Theme.surface2.opacity(0.4))
    }

    @ViewBuilder
    private var formatHint: some View {
        switch format {
        case .codex:
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.system(size: 9))
                Text("~/.codex/sessions/").font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(Theme.textTertiary)
            .help("Save here so the Codex CLI can resume it")
        case .gemini:
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.system(size: 9))
                Text("~/.gemini/tmp/").font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(Theme.textTertiary)
            .help("Save here so the Gemini CLI can resume it")
        default:
            EmptyView()
        }
    }

    // MARK: - Preview

    private var previewPane: some View {
        let r = result
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(r.suggestedFilename)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text("· \(r.messageCount) messages\(r.toolCallCount > 0 ? " · \(r.toolCallCount) tools" : "") · \(formatBytes(r.content.utf8.count))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Theme.surface2.opacity(0.6))

            ScrollView([.vertical, .horizontal]) {
                Text(previewText(r.content))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.codeBackground)
        }
    }

    /// Preview cap so a giant export doesn't make the sheet sluggish.
    private func previewText(_ s: String) -> String {
        let cap = 16_000
        if s.count > cap {
            return String(s.prefix(cap)) + "\n\n…[\(s.count - cap) more characters truncated in preview — full content will be saved/copied]"
        }
        return s
    }

    private func formatBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024.0) }
        return String(format: "%.2f MB", Double(n) / (1024.0 * 1024.0))
    }

    // MARK: - Actions

    private var actionsBar: some View {
        let r = result
        return HStack(spacing: 8) {
            if let saved = savedTo {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.toolTint)
                    Text("Saved · ")
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        NSWorkspace.shared.selectFile(saved, inFileViewerRootedAtPath: (saved as NSString).deletingLastPathComponent)
                    } label: {
                        Text(saved)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
                .font(.system(size: 10, design: .monospaced))
            } else if copied {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.toolTint)
                    Text("Copied to clipboard")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.system(size: 10, design: .monospaced))
            }

            Spacer()

            Button("Copy to Clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(r.content, forType: .string)
                copied = true
                savedTo = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // For Codex/Gemini, expose direct "Save to default location" — it
            // drops the file straight into the right CLI dir so it shows up
            // in the resume picker. For Markdown/JSON, only the standard
            // save dialog is offered.
            if let suggestedDir = r.suggestedDirectory {
                Button("Save to \(format.displayName) directory") {
                    saveToDefaultLocation(r: r, dir: suggestedDir)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .help("Save to \(suggestedDir)")
            }

            Button("Save As…") {
                saveAs(r: r)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - File operations

    private func saveAs(r: ExportService.Result) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = r.suggestedFilename
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if let dir = r.suggestedDirectory {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try r.content.write(to: url, atomically: true, encoding: .utf8)
            savedTo = url.path
            copied = false
        } catch {
            appState.toastMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveToDefaultLocation(r: ExportService.Result, dir: String) {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(r.suggestedFilename)
        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true
            )
            try r.content.write(to: url, atomically: true, encoding: .utf8)
            savedTo = url.path
            copied = false
        } catch {
            appState.toastMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Format pill

private struct FormatPill: View {
    let label: String
    let icon: String
    let active: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 11, weight: active ? .bold : .medium, design: .monospaced))
            }
            .foregroundStyle(active ? Theme.accent : (hovered ? Theme.text : Theme.textSecondary))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(
                active
                    ? Theme.accent.opacity(0.16)
                    : (hovered ? Theme.surface2 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(active ? Theme.accent.opacity(0.45) : Theme.border.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
