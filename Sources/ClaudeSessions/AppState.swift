import SwiftUI
import AppKit
import ContinuousBackup

/// User preference for what "Extract" does when clicked without holding modifier keys.
enum ExtractMode: String {
    case newSession = "newSession"   // A — write cleaned JSONL, open with --resume (default)
    case pipedPrompt = "pipedPrompt" // B — extract text, pipe into fresh `claude`
}

@MainActor
final class AppState: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedSessionId: String?
    @Published var currentConversation: Conversation?
    @Published var isLoading = false
    @Published var sidebarSearchText = ""

    // Filter state
    @Published var showUserMessages = true
    @Published var showAssistantMessages = true
    @Published var showToolMessages = true
    @Published var showSystemMessages = false

    // Edit state
    @Published var isDirty = false
    @Published var editingMessageId: String?
    @Published var editedTexts: [String: String] = [:]
    @Published var deletedMessageIds: Set<String> = []

    // Mode
    @Published var isJSONMode = false
    @Published var isReadingMode = false
    @Published var expandedToolBatchIds: Set<String> = []
    @Published var isSelectMode = false
    @Published var selectedMessageIds: Set<String> = []
    @Published var showExportSheet = false
    @Published var showSearchSheet = false
    @Published var moveSessionContext: MoveSessionContext?

    struct MoveSessionContext: Identifiable {
        let id = UUID()
        let session: SessionInfo
        let sourceProject: Project
    }

    // Settings (AppStorage-backed)
    @AppStorage("displayName") var displayName = "You"
    @AppStorage("theme") var theme = "system"
    @AppStorage("extractMode") var extractModeRaw: String = ExtractMode.newSession.rawValue

    /// Per-target export usage. Encoded as JSON in @AppStorage so we can
    /// promote whichever agent the user picks most often into the primary
    /// position of the export-to-agent split-button.
    @AppStorage("agentExportUsage") private var agentExportUsageRaw: String = ""

    var extractMode: ExtractMode {
        get { ExtractMode(rawValue: extractModeRaw) ?? .newSession }
        set { extractModeRaw = newValue.rawValue }
    }

    // Toast feedback
    @Published var toastMessage: String?

    // Archive view state
    @Published var showArchiveSheet = false
    @Published var showBackupVaultSheet = false

    // Context detail sheet
    @Published var showContextSheet = false

    // Embedded chat composer (Phase 2)
    @Published var composerText: String = ""
    @Published var isComposerSending: Bool = false
    @AppStorage("embeddedChatEnabled") var embeddedChatEnabled: Bool = true

    /// IDs of display messages that just arrived from a JSONL append.
    /// Cleared ~1.5s after they show up. Used by ConversationView to fade
    /// new bubbles in and trigger an auto-scroll. Empty during normal
    /// loads (e.g. switching to a different session).
    @Published var recentlyArrivedMessageIds: Set<String> = []
    /// Bumped whenever new messages arrive so views can react via onChange.
    @Published var lastAppendAt: Date = .distantPast

    /// Cached metrics for the currently open conversation. Recomputed on
    /// `selectSession` so it stays in sync.
    @Published private(set) var contextMetrics: ContextMetrics.Result?

    // Services
    private let scanner = ProjectScanner()
    private let parser = ConversationParser()
    private let backupService = BackupService()
    private let writer = ConversationWriter()
    private let cleaner = CleanConversationService()
    private let sessionCreator = SessionCreator()
    private let forker = SessionForker()
    let archiveService = ArchiveService()
    private let contextMetricsService = ContextMetrics()
    let backupEngine = BackupEngine()
    private let claudeRunner = ClaudeRunner()
    let mcpServer = MCPServer()  // tools registered & started in P3.T03+

    @AppStorage("continuousBackupEnabled") var continuousBackupEnabled: Bool = true

    private var conversationCache: [String: CachedConversation] = [:]
    private let maxCacheSize = 10
    private let fileWatcher = FileWatcher()

    /// In-flight load task. Cancelled when a new session is selected, so
    /// stale parses don't keep running and piling up memory pressure.
    private var inflightLoad: Task<Void, Never>?

    /// Absolute upper bound on JSONL file size we'll try to load. Parsing
    /// runs off-main and the UI stays responsive during, but at some point
    /// memory + parse time become genuinely abusive. 200MB is the sane
    /// ceiling — anything bigger is almost certainly a runaway log file
    /// rather than a real conversation.
    private let maxLoadableFileSize: Int64 = 200_000_000

    struct CachedConversation {
        let conversation: Conversation
        let fileModDate: Date
        var lastAccessed: Date
    }

    // MARK: - Init

    init() {
        if continuousBackupEnabled {
            backupEngine.start()
        }
    }

    /// Toggle the continuous-backup engine. Persists the preference too.
    func setContinuousBackupEnabled(_ enabled: Bool) {
        continuousBackupEnabled = enabled
        if enabled {
            backupEngine.start()
        } else {
            backupEngine.stop()
        }
    }

    // MARK: - Project loading

    func loadProjects() async {
        isLoading = true
        let discovered = await scanner.scan()
        projects = discovered
        isLoading = false
    }

    func selectSession(_ sessionInfo: SessionInfo) async {
        // Cancel any previous load — prevents work pileup when the user
        // clicks multiple sessions rapidly.
        inflightLoad?.cancel()
        inflightLoad = nil

        selectedSessionId = sessionInfo.id

        // Fast path: cached + same mtime
        if let cached = conversationCache[sessionInfo.id] {
            let currentModDate = FileManager.default.modificationDate(at: sessionInfo.filePath)
            if currentModDate == cached.fileModDate {
                conversationCache[sessionInfo.id]?.lastAccessed = Date()
                currentConversation = cached.conversation
                let cachedConv = cached.conversation
                let cachedId = sessionInfo.id
                Task {
                    let m = await Task.detached(priority: .userInitiated) {
                        ContextMetrics().compute(for: cachedConv)
                    }.value
                    guard self.selectedSessionId == cachedId else { return }
                    self.contextMetrics = m
                }
                resetEditState()
                isJSONMode = false
                return
            }
        }

        // Size check serves two purposes:
        //   1. Hint the user that big files take longer (so they don't think
        //      the app froze when a 50MB session takes ~5s to parse).
        //   2. Hard-refuse pathological files — runaway logs, gigabyte-class
        //      sessions where parse cost + memory become abusive.
        var bigFileSize: Double? = nil
        if let attrs = try? FileManager.default.attributesOfItem(atPath: sessionInfo.filePath),
           let size = attrs[.size] as? Int64 {
            if size > maxLoadableFileSize {
                let mb = Double(size) / 1_000_000
                showToast("Session too large to load — \(String(format: "%.1f", mb))MB exceeds the \(maxLoadableFileSize / 1_000_000)MB limit.")
                selectedSessionId = nil
                return
            }
            if size > 20_000_000 {
                bigFileSize = Double(size) / 1_000_000
            }
        }
        if let mb = bigFileSize {
            showToast("Loading large session (\(String(format: "%.0f", mb))MB) — this may take a moment…")
        }

        // Slow path — off main, cancellable.
        isLoading = true
        currentConversation = nil
        contextMetrics = nil

        let sessionId = sessionInfo.id
        let filePath = sessionInfo.filePath

        // Keep the task around so we can cancel it on next select.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(sessionId: sessionId, filePath: filePath)
        }
        inflightLoad = task
        _ = await task.value
    }

    /// Orchestrates the actual file read + parse. Runs on MainActor but
    /// delegates the heavy work to a detached task so the UI stays free.
    /// Respects Task.isCancelled — bails out cleanly if the user moved on.
    private func performLoad(sessionId: String, filePath: String) async {
        let loaded: (Conversation, Date)? = await Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()

                let t0 = Date()
                let size = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int) ?? -1
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let tRead = Date().timeIntervalSince(t0) * 1000
                print("[ClaudeSessions] read \(sessionId.prefix(8)) — \(size) bytes in \(Int(tRead))ms")
                try Task.checkCancellation()

                let t1 = Date()
                let parser = ConversationParser()
                let conv = parser.parse(data: data, sessionId: sessionId, filePath: filePath)
                let tParse = Date().timeIntervalSince(t1) * 1000
                print("[ClaudeSessions] parse \(sessionId.prefix(8)) — \(conv.rawEntries.count) entries, \(conv.displayMessages.count) display msgs in \(Int(tParse))ms")
                try Task.checkCancellation()

                let mod = (try? FileManager.default
                    .attributesOfItem(atPath: filePath)[.modificationDate] as? Date) ?? Date()
                return (conv, mod)
            } catch is CancellationError {
                print("[ClaudeSessions] load cancelled \(sessionId.prefix(8))")
                return nil
            } catch {
                print("[ClaudeSessions] load failed \(sessionId.prefix(8)): \(error)")
                return nil
            }
        }.value

        // User clicked away?
        guard selectedSessionId == sessionId else {
            isLoading = false
            return
        }

        if let (conversation, modDate) = loaded {
            // Diff to find newly-arrived messages (live appends from
            // claude -p, file watcher reloads, etc.). Skip the diff if
            // we're loading a different session or the previous load is
            // empty — those aren't "appends" from the user's perspective.
            let priorIds: Set<String>? = {
                guard let prior = currentConversation,
                      prior.sessionId == conversation.sessionId,
                      !prior.displayMessages.isEmpty
                else { return nil }
                return Set(prior.displayMessages.map(\.id))
            }()
            let newIds: Set<String> = {
                guard let priorIds else { return [] }
                let currentIds = Set(conversation.displayMessages.map(\.id))
                return currentIds.subtracting(priorIds)
            }()

            currentConversation = conversation
            resetEditState()
            isJSONMode = false

            if !newIds.isEmpty {
                recentlyArrivedMessageIds = newIds
                lastAppendAt = Date()
                // Clear the "new" flag after the fade-in window so the
                // animation doesn't re-fire if anything else triggers a
                // re-render.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run {
                        self?.recentlyArrivedMessageIds.subtract(newIds)
                    }
                }
            }

            conversationCache[sessionId] = CachedConversation(
                conversation: conversation, fileModDate: modDate, lastAccessed: Date()
            )
            evictCacheIfNeeded()

            fileWatcher.watch(path: filePath)
            fileWatcher.onChange = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.handleExternalFileChange(sessionId: sessionId, filePath: filePath)
                }
            }

            // Metrics — also off main, also cancellable via selectedSessionId check.
            let metrics = await Task.detached(priority: .userInitiated) {
                ContextMetrics().compute(for: conversation)
            }.value
            guard selectedSessionId == sessionId else {
                isLoading = false
                return
            }
            contextMetrics = metrics
        } else {
            currentConversation = nil
        }
        isLoading = false
    }

    private func handleExternalFileChange(sessionId: String, filePath: String) {
        guard !isDirty else { return }
        conversationCache.removeValue(forKey: sessionId)
        if let session = findSession(id: sessionId) {
            Task { await selectSession(session) }
        }
    }

    // MARK: - Editing

    func startEditing(messageId: String, currentText: String) {
        if let currentId = editingMessageId, currentId != messageId {
            commitEdit(messageId: currentId)
        }
        editingMessageId = messageId
        if editedTexts[messageId] == nil {
            editedTexts[messageId] = currentText
        }
    }

    func commitEdit(messageId: String) {
        editingMessageId = nil
        if editedTexts[messageId] != nil {
            isDirty = true
        }
    }

    func cancelEdit(messageId: String, originalText: String) {
        editedTexts.removeValue(forKey: messageId)
        editingMessageId = nil
        isDirty = !editedTexts.isEmpty || !deletedMessageIds.isEmpty
    }

    func deleteMessage(messageId: String) {
        deletedMessageIds.insert(messageId)
        isDirty = true
    }

    func undeleteMessage(messageId: String) {
        deletedMessageIds.remove(messageId)
        isDirty = !editedTexts.isEmpty || !deletedMessageIds.isEmpty
    }

    func getDisplayText(messageId: String, originalText: String) -> String {
        editedTexts[messageId] ?? originalText
    }

    private func resetEditState() {
        isDirty = false
        editingMessageId = nil
        editedTexts = [:]
        deletedMessageIds = []
        expandedToolBatchIds = []
    }

    // MARK: - Save (non-destructive: forks to a new session, archives original)

    /// Save edits by forking to a NEW session file. The original session is
    /// kept intact (and renamed to `<title> · archived` in the index) so the
    /// user can always go back to it. The edited version becomes the active
    /// session and keeps the original's title.
    func save() async {
        guard isDirty, let conversation = currentConversation else { return }
        guard let cwd = conversation.resolvedCwd else {
            showToast("Cannot determine project directory for save")
            return
        }
        guard let originalSession = findSession(id: conversation.sessionId) else {
            showToast("Cannot find original session metadata")
            return
        }

        let originalTitle = originalSession.title
        let archivedTitle = archivedSuffix(for: originalTitle)

        // 1. Fork the conversation into a new JSONL with edits applied
        let result = forker.fork(
            conversation: conversation,
            editedTexts: editedTexts,
            deletedMessageIds: deletedMessageIds
        )

        if result.jsonl.isEmpty {
            showToast("Nothing to save — all content was deleted")
            return
        }

        // 2. Pull some metadata for the index
        let firstPrompt = extractFirstUserPrompt(conversation: conversation)
        let gitBranch = conversation.rawEntries.first(where: { $0.entry.gitBranch != nil })?.entry.gitBranch

        do {
            // 3. Belt-and-suspenders: also back up the original JSONL to our
            //    dedicated backup directory before doing anything else.
            _ = try backupService.backup(filePath: conversation.filePath, sessionId: conversation.sessionId)

            // 4. Create the new (edited) session on disk and in the index
            let created = try sessionCreator.create(
                jsonl: result.jsonl,
                sessionId: result.sessionId,
                cwd: cwd,
                title: originalTitle,
                firstPrompt: firstPrompt,
                userCount: result.messageCount,
                assistantCount: 0,           // already baked into messageCount above
                gitBranch: gitBranch
            )

            // 5. Rename the original in the index → "<title> · archived"
            sessionCreator.updateSessionTitle(
                projectCwd: cwd,
                sessionId: conversation.sessionId,
                newTitle: archivedTitle
            )

            // 6. Clear edit state + refresh sidebar
            let oldId = conversation.sessionId
            isDirty = false
            editedTexts = [:]
            editingMessageId = nil
            deletedMessageIds = []
            conversationCache.removeValue(forKey: oldId)

            await loadProjects()

            // 7. Auto-select the new session so the user sees their edits applied
            if let newSession = findSession(id: created.sessionId) {
                await selectSession(newSession)
            }

            showToast("Saved as new session · original archived")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    private func archivedSuffix(for title: String) -> String {
        // If the title already ends in · archived, don't re-archive forever
        if title.hasSuffix("· archived") || title.contains("· archived ") {
            return title
        }
        return "\(title) · archived"
    }

    private func extractFirstUserPrompt(conversation: Conversation) -> String? {
        for d in conversation.displayMessages {
            if case .userText(let m) = d, !m.isCompactSummary {
                let text = editedTexts[m.id] ?? m.text
                return String(text.prefix(200))
            }
        }
        return nil
    }

    // MARK: - Extract (the headline feature)

    /// Copy the FULL transcript — every message, tool call, tool result, system event.
    /// Formatted as a readable log, not JSON.
    func copyFullTranscriptToClipboard() {
        guard let conv = currentConversation else { return }
        let lines = ClipboardService.formatFullTranscript(
            displayMessages: conv.displayMessages,
            displayName: displayName,
            editedTexts: editedTexts,
            deletedMessageIds: deletedMessageIds
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines, forType: .string)
        showToast("Full transcript copied")
    }

    /// Copy the cleaned dialogue text to the clipboard. Never opens Claude Code.
    func extractToClipboard() {
        guard let conv = currentConversation else { return }
        let result = cleaner.clean(
            conversation: conv,
            editedTexts: editedTexts,
            deletedMessageIds: deletedMessageIds,
            displayName: displayName
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.plainText, forType: .string)
        showToast("Copied \(result.userCount + result.assistantCount) messages")
    }

    /// Extract using the user's preferred mode from Settings, then open Claude Code.
    func extractAndOpenInClaude() {
        guard let conv = currentConversation else { return }
        guard let cwd = conv.resolvedCwd else {
            showToast("Cannot determine project directory")
            return
        }

        switch extractMode {
        case .newSession:
            extractAsNewSession(conversation: conv, cwd: cwd)
        case .pipedPrompt:
            extractAsPipedPrompt(conversation: conv, cwd: cwd)
        }
    }

    /// Continue from a specific message: fork the conversation truncated up
    /// to and including this message, write it as a new JSONL session, and
    /// open `claude --resume` against it. The original is untouched.
    func continueFromMessage(id messageId: String) {
        guard let conv = currentConversation, let cwd = conv.resolvedCwd else {
            showToast("Cannot determine project directory")
            return
        }
        guard let forked = forker.forkUpToMessage(conversation: conv, cutoffMessageId: messageId) else {
            showToast("Could not find message to continue from")
            return
        }
        let title = generateSessionTitle(from: conv).replacingOccurrences(of: "· clean ·", with: "· continue ·")
        let firstPrompt: String? = {
            for m in conv.displayMessages {
                if case .userText(let utm) = m { return utm.text }
            }
            return nil
        }()
        let gitBranch = conv.rawEntries.first(where: { $0.entry.gitBranch != nil })?.entry.gitBranch

        do {
            let created = try sessionCreator.create(
                jsonl: forked.jsonl,
                sessionId: forked.sessionId,
                cwd: cwd,
                title: title,
                firstPrompt: firstPrompt,
                userCount: forked.messageCount,
                assistantCount: 0,
                gitBranch: gitBranch
            )
            showToast("Forked at message · opening Claude Code…")
            ProcessLauncher.resumeSession(
                sessionId: created.sessionId,
                cwd: created.projectCwd,
                displayName: title
            )
            Task { await loadProjects() }
        } catch {
            showToast("Continue-from failed: \(error.localizedDescription)")
        }
    }

    /// Mode A: write a new JSONL session file and open with `claude --resume`.
    func extractAsNewSession(conversation conv: Conversation, cwd: String) {
        let result = cleaner.clean(
            conversation: conv,
            editedTexts: editedTexts,
            deletedMessageIds: deletedMessageIds,
            displayName: displayName
        )

        if result.jsonl.isEmpty {
            showToast("No conversation text to extract")
            return
        }

        let title = generateSessionTitle(from: conv)
        let firstPrompt = result.plainText.components(separatedBy: "\n").dropFirst().first
        let gitBranch = conv.rawEntries.first(where: { $0.entry.gitBranch != nil })?.entry.gitBranch

        do {
            let created = try sessionCreator.create(
                jsonl: result.jsonl,
                sessionId: result.sessionId,
                cwd: cwd,
                title: title,
                firstPrompt: firstPrompt,
                userCount: result.userCount,
                assistantCount: result.assistantCount,
                gitBranch: gitBranch
            )

            showToast("Created clean session · opening Claude Code…")
            ProcessLauncher.resumeSession(
                sessionId: created.sessionId,
                cwd: created.projectCwd,
                displayName: title
            )

            // Refresh sidebar so the new session appears
            Task { await loadProjects() }
        } catch {
            showToast("Extract failed: \(error.localizedDescription)")
        }
    }

    /// Mode B: extract plain-text dialogue and pipe into a new `claude` session.
    func extractAsPipedPrompt(conversation conv: Conversation, cwd: String) {
        let result = cleaner.clean(
            conversation: conv,
            editedTexts: editedTexts,
            deletedMessageIds: deletedMessageIds,
            displayName: displayName
        )
        if result.plainText.isEmpty {
            showToast("No conversation text to extract")
            return
        }
        let title = generateSessionTitle(from: conv)
        showToast("Opening Claude Code with piped prompt…")
        ProcessLauncher.newSessionFromPipedPrompt(
            promptText: result.plainText,
            cwd: cwd,
            displayName: title
        )
    }

    // MARK: - Export to other coding agents

    /// Read the per-target use-counts. Picks up changes made via
    /// `recordAgentExport` since the JSON lives in @AppStorage.
    var agentExportUsage: [AgentTarget: Int] {
        guard let data = agentExportUsageRaw.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        var out: [AgentTarget: Int] = [:]
        for (k, v) in raw {
            if let target = AgentTarget(rawValue: k) { out[target] = v }
        }
        return out
    }

    /// The agent shown as the primary "Export to" option. Highest-used wins;
    /// Codex is the seed default until the user has clicked anything.
    var defaultAgentTarget: AgentTarget {
        let usage = agentExportUsage
        if let top = usage.max(by: { $0.value < $1.value }) { return top.key }
        return .codex
    }

    private func recordAgentExport(_ target: AgentTarget) {
        var usage = agentExportUsage
        usage[target, default: 0] += 1
        let raw: [String: Int] = Dictionary(uniqueKeysWithValues: usage.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw),
           let s = String(data: data, encoding: .utf8) {
            agentExportUsageRaw = s
        }
    }

    /// Hand the current conversation off to another coding agent.
    ///
    /// For Codex/Gemini we have native session formats — the file lands in
    /// the agent's resume directory and we boot the CLI in iTerm so the
    /// session shows up in its picker.
    ///
    /// For opencode we drop a markdown briefing into a temp file, copy to
    /// clipboard, and launch the CLI; the user pastes the prompt as the
    /// first message. For Cursor we open the markdown directly in the IDE.
    func exportToAgent(_ target: AgentTarget) {
        guard let conv = currentConversation else {
            showToast("No conversation open to export")
            return
        }
        let cwd = conv.resolvedCwd
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let title = findSession(id: conv.sessionId)?.title ?? "conversation"

        recordAgentExport(target)

        switch target {
        case .codex:
            handoff(conv: conv, title: title, cwd: cwd, format: .codex,
                    target: target, launchInTerminal: true, copyToClipboard: false)
        case .gemini:
            handoff(conv: conv, title: title, cwd: cwd, format: .gemini,
                    target: target, launchInTerminal: true, copyToClipboard: false)
        case .opencode:
            handoff(conv: conv, title: title, cwd: cwd, format: .opencode,
                    target: target, launchInTerminal: true, copyToClipboard: true)
        case .cursor:
            handoff(conv: conv, title: title, cwd: cwd, format: .cursor,
                    target: target, launchInTerminal: false, copyToClipboard: true)
        }
    }

    private func handoff(
        conv: Conversation,
        title: String,
        cwd: String,
        format: ExportService.Format,
        target: AgentTarget,
        launchInTerminal: Bool,
        copyToClipboard: Bool
    ) {
        let result = ExportService.export(
            format: format,
            conversation: conv,
            title: title,
            includeTools: false,
            displayName: displayName,
            editedTexts: editedTexts,
            deletedMessageIds: deletedMessageIds
        )

        // Decide where the file lives. Codex/Gemini have a fixed CLI dir;
        // opencode/Cursor don't, so we use the system temp dir.
        let dir = result.suggestedDirectory ?? NSTemporaryDirectory()
        let outURL = URL(fileURLWithPath: dir).appendingPathComponent(result.suggestedFilename)

        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try result.content.write(to: outURL, atomically: true, encoding: .utf8)
        } catch {
            showToast("Export to \(target.displayName) failed: \(error.localizedDescription)")
            return
        }

        if copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.content, forType: .string)
        }

        if launchInTerminal, let bin = target.cliBinary {
            ProcessLauncher.launchAgentCLI(binary: bin, cwd: cwd)
        } else if target == .cursor {
            ProcessLauncher.openInCursor(filePath: outURL.path)
        }

        let toastBits: String = {
            switch target {
            case .codex, .gemini:
                return "Saved to \(target.displayName) · launching CLI…"
            case .opencode:
                return "Briefing copied + saved · opening opencode…"
            case .cursor:
                return "Briefing opened in Cursor · also copied to clipboard"
            }
        }()
        showToast(toastBits)
    }

    // MARK: - Delete (move to macOS Trash — recoverable until user empties Trash)

    /// Confirmation state for an in-progress delete. When set, the UI shows a
    /// confirmation dialog. On confirm we actually recycle the JSONL.
    @Published var pendingDelete: SessionInfo?

    func requestDeleteSession(_ session: SessionInfo) {
        pendingDelete = session
    }

    func confirmDeleteSession(_ session: SessionInfo) async {
        pendingDelete = nil
        // Close the conversation if it's the one currently open
        if selectedSessionId == session.id {
            closeCurrentSession()
        }
        conversationCache.removeValue(forKey: session.id)

        let fileURL = URL(fileURLWithPath: session.filePath)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.recycle([fileURL]) { _, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            // Also clean up sessions-index.json entry if we can find the project
            if let project = projects.first(where: { $0.sessions.contains { $0.id == session.id } }) {
                let cwd = resolveCwd(for: project) ?? project.originalPath
                sessionCreator.removeSessionFromIndex(projectCwd: cwd, sessionId: session.id)
            }
            await loadProjects()
            showToast("Moved to Trash · \(session.title)")
        } catch {
            showToast("Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Archive (physical file movement)

    /// Move a session file into the archive directory. The session
    /// disappears from `~/.claude/projects/` so Claude Code won't see it.
    func archiveSession(_ session: SessionInfo) async {
        guard let project = projects.first(where: { $0.sessions.contains { $0.id == session.id } }) else {
            showToast("Cannot archive — project not found")
            return
        }
        do {
            // Close the conversation if it's the one currently open
            if selectedSessionId == session.id {
                closeCurrentSession()
            }
            try archiveService.archive(session: session, projectId: project.id, projectName: project.name)
            conversationCache.removeValue(forKey: session.id)
            await loadProjects()
            showToast("Archived · \(session.title)")
        } catch {
            showToast("Archive failed: \(error.localizedDescription)")
        }
    }

    /// Move an archived session back to its original project directory.
    func restoreArchivedSession(_ entry: ArchiveService.ArchivedEntry) async {
        do {
            try archiveService.restore(entry: entry)
            await loadProjects()
            showToast("Restored · \(entry.title)")
        } catch {
            showToast("Restore failed: \(error.localizedDescription)")
        }
    }

    /// Irreversible — remove the archived file from disk entirely.
    func permanentlyDeleteArchived(_ entry: ArchiveService.ArchivedEntry) {
        do {
            try archiveService.permanentlyDelete(entry: entry)
            showToast("Deleted permanently")
        } catch {
            showToast("Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Move / duplicate to another project

    /// Launch the project picker for moving (duplicating) a session.
    func beginMoveSession(_ session: SessionInfo) {
        guard let project = projects.first(where: { $0.sessions.contains { $0.id == session.id } }) else { return }
        moveSessionContext = MoveSessionContext(session: session, sourceProject: project)
    }

    /// Actually copy the session's JSONL into the target project.
    /// Never deletes or modifies the source — this is a duplicate.
    func copySessionToProject(session: SessionInfo, sourceProject: Project, target: Project) async {
        moveSessionContext = nil

        guard target.id != sourceProject.id else {
            showToast("Source and target are the same project")
            return
        }
        guard let targetCwd = resolveCwd(for: target) else {
            showToast("Cannot determine target project path")
            return
        }

        do {
            let created = try sessionCreator.copyToProject(
                sourceFilePath: session.filePath,
                sourceTitle: session.title,
                sourceProjectName: sourceProject.name,
                targetCwd: targetCwd
            )
            showToast("Copied to \(target.name)")
            await loadProjects()

            // Select the new copy in the target project
            if let newSession = findSession(id: created.sessionId) {
                await selectSession(newSession)
            }
        } catch {
            showToast("Copy failed: \(error.localizedDescription)")
        }
    }

    /// Resolve the filesystem cwd for a project, preferring sessionsIndex.originalPath
    /// and falling back to the stored path on the project.
    private func resolveCwd(for project: Project) -> String? {
        // Ask any session in the project for its projectPath (from index) — most reliable
        if let sessionWithPath = project.sessions.first(where: { $0.projectPath != nil }),
           let p = sessionWithPath.projectPath {
            return p
        }
        return project.originalPath
    }

    // MARK: - Session renaming (inline)

    /// Rename the current session in sessions-index.json. Only updates the index,
    /// doesn't touch the JSONL file itself.
    func renameCurrentSession(to newTitle: String) {
        guard let conv = currentConversation, let cwd = conv.resolvedCwd else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sessionCreator.updateSessionTitle(projectCwd: cwd, sessionId: conv.sessionId, newTitle: trimmed)
        showToast("Renamed")
        Task { await loadProjects() }
    }

    // MARK: - Helpers

    /// Title of the currently-open session, looked up from the projects list.
    /// nil if no session is open.
    var currentSessionTitle: String? {
        guard let id = selectedSessionId else { return nil }
        for project in projects {
            if let s = project.sessions.first(where: { $0.id == id }) {
                return s.title
            }
        }
        return nil
    }

    private func generateSessionTitle(from conv: Conversation) -> String {
        // Find the source session's existing title
        let sourceTitle: String = {
            for project in projects {
                if let s = project.sessions.first(where: { $0.id == conv.sessionId }) {
                    return s.title
                }
            }
            return "Clean"
        }()

        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        let ts = f.string(from: Date())
        return "\(sourceTitle) · clean · \(ts)"
    }

    /// Send the composer's current text into the open conversation via
    /// `claude -p --resume`. The CLI appends to the JSONL; FileWatcher
    /// (already wired in `selectSession`) picks up the new entries and
    /// the conversation re-loads, surfacing the user prompt + Claude's
    /// response inline.
    func submitComposer() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isComposerSending else { return }
        guard let conv = currentConversation else {
            showToast("Open a conversation first")
            return
        }
        guard let cwd = conv.resolvedCwd else {
            showToast("Couldn't resolve project working directory")
            return
        }

        let sessionId = conv.sessionId
        isComposerSending = true
        composerText = ""

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.claudeRunner.run(sessionId: sessionId,
                                                     prompt: text,
                                                     cwd: cwd)
            await MainActor.run {
                self.isComposerSending = false
                switch outcome {
                case .success:
                    self.showToast("Sent · waiting for Claude…")
                case .failure(let code, let stderr):
                    let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let detail = trimmed.isEmpty ? "exit \(code)" : trimmed.split(separator: "\n").last.map(String.init) ?? trimmed
                    self.showToast("claude failed: \(detail)")
                case .cancelled:
                    self.showToast("Stopped")
                case .launchFailed(let reason):
                    self.showToast("Couldn't launch claude: \(reason)")
                }
            }
        }
    }

    /// Cancel the in-flight composer send (Phase 2 / T05 — Stop button).
    func cancelComposer() {
        claudeRunner.cancel()
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    /// Close the currently open conversation and return to the dashboard.
    func closeCurrentSession() {
        if isDirty {
            // Discard pending edits rather than silently losing them.
            // Future enhancement: prompt the user.
        }
        currentConversation = nil
        contextMetrics = nil
        selectedSessionId = nil
        resetEditState()
        isJSONMode = false
        fileWatcher.stop()
    }

    func findSession(id: String) -> SessionInfo? {
        for project in projects {
            if let session = project.sessions.first(where: { $0.id == id }) {
                return session
            }
        }
        return nil
    }

    private func evictCacheIfNeeded() {
        while conversationCache.count > maxCacheSize {
            if let oldest = conversationCache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) {
                conversationCache.removeValue(forKey: oldest.key)
            }
        }
    }
}

extension FileManager {
    func modificationDate(at path: String) -> Date? {
        try? attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
