import AppKit

/// Launches Claude Code CLI in the user's terminal.
///
/// Strategy: write a `.command` file (an executable shell script with a
/// well-known macOS extension) and ask `NSWorkspace` to open it. macOS
/// routes `.command` files to whatever app the user has registered as the
/// handler — Terminal.app by default, but the user can change this once
/// in Finder ("Open With → Other → <terminal> → Always Open With") and
/// from then on every `.command` file opens in their preferred terminal.
///
/// This means we don't write per-terminal code (no AppleScript for iTerm2,
/// no IPC for Ghostty, no Warp-specific shim). Anything that registers as
/// a `.command` handler works out of the box: iTerm2, Warp, Ghostty,
/// kitty, Alacritty, Hyper, Wezterm, Tabby, etc.
enum ProcessLauncher {

    // MARK: - Public API

    /// Resume an existing Claude session.
    static func resumeSession(sessionId: String, cwd: String, displayName: String? = nil) {
        var cmd = "claude --resume \(shellQuote(sessionId))"
        if let n = displayName, !n.isEmpty {
            cmd += " --name \(shellQuote(n))"
        }
        launch(command: cmd, cwd: cwd)
    }

    /// Start a new Claude session by piping a text prompt.
    /// Writes the prompt to a temp file so shells don't choke on length/quotes.
    static func newSessionFromPipedPrompt(promptText: String, cwd: String, displayName: String? = nil) {
        let tempPath = NSTemporaryDirectory() + "claude-prompt-\(UUID().uuidString).txt"
        try? promptText.write(toFile: tempPath, atomically: true, encoding: .utf8)

        var cmd = "cat \(shellQuote(tempPath)) | claude"
        if let n = displayName, !n.isEmpty {
            cmd += " --name \(shellQuote(n))"
        }
        launch(command: cmd, cwd: cwd)
    }

    /// Back-compat aliases.
    static func openInClaude(sessionId: String, projectPath: String) {
        resumeSession(sessionId: sessionId, cwd: projectPath, displayName: nil)
    }
    static func openNewClaudeSession(projectPath: String, promptText: String) {
        newSessionFromPipedPrompt(promptText: promptText, cwd: projectPath, displayName: nil)
    }

    /// Launch an arbitrary CLI binary (codex / gemini / opencode) at `cwd`.
    /// Used by export-to-agent so the new agent boots directly into the
    /// project the conversation came from.
    static func launchAgentCLI(binary: String, cwd: String) {
        launch(command: binary, cwd: cwd)
    }

    /// Launch an agent CLI with a prompt file piped into stdin. Used by
    /// Cursor/opencode-style flows where the agent doesn't support a
    /// "resume" wire format but can ingest a markdown briefing.
    static func launchAgentCLIWithPipedFile(binary: String, filePath: String, cwd: String) {
        let cmd = "cat \(shellQuote(filePath)) | \(binary)"
        launch(command: cmd, cwd: cwd)
    }

    /// Open a path in Cursor (or any registered macOS app). Falls back
    /// silently if Cursor isn't installed — caller should already have
    /// copied the markdown to the clipboard.
    static func openInCursor(filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        guard let cursor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") else {
            NSWorkspace.shared.open(url)
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: cursor, configuration: cfg)
    }

    // MARK: - Universal launcher

    /// Build a `.command` file containing the cd + command + an interactive
    /// shell at the end (so the window stays open), make it executable,
    /// then ask `NSWorkspace` to open it. macOS routes the open to whatever
    /// the user has set as the default handler for `.command` files.
    private static func launch(command: String, cwd: String) {
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // We use ~/Library/Application Support/ClaudeSessions/launch/ rather
        // than /tmp because some terminals (notably Ghostty) prompt the user
        // before executing arbitrary scripts under /var/folders.
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ClaudeSessions/launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let scriptURL = supportDir.appendingPathComponent("launch-\(UUID().uuidString).command")
        let body = """
        #!/bin/bash
        cd \(shellQuote(cwd)) || exit 1
        \(command)
        exec \(userShell) -l
        """
        do {
            try body.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: scriptURL.path)
        } catch {
            print("ProcessLauncher: failed to write .command script: \(error)")
            return
        }

        // Open with the system's default `.command` handler. Users can
        // change this in Finder: right-click any .command → Open With →
        // Other → <their terminal> → check "Always Open With". After that,
        // resume / extract / open-CLI all use that terminal.
        NSWorkspace.shared.open(scriptURL)

        // Schedule cleanup ~10 minutes later. The terminal has plenty of
        // time to spawn and read the script before then.
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 600) {
            try? FileManager.default.removeItem(at: scriptURL)
        }
    }

    // MARK: - Helpers

    /// POSIX shell single-quote an argument. Handles embedded single quotes.
    /// `abc'def` becomes `'abc'"'"'def'` — safe for `cd`, `cat`, etc.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
