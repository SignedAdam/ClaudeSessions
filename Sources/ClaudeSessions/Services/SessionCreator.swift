import Foundation

/// Creates a brand-new Claude Code session on disk from cleaned JSONL content.
///
/// Key rules enforced:
/// - The JSONL file is written to `~/.claude/projects/<cwd-slug>/<new-uuid>.jsonl`
///   where `<cwd-slug>` is the working directory converted to Claude Code's
///   on-disk project slug format.
///   `claude --resume <id>` only works when invoked from the matching cwd,
///   so the file location must match the cwd we'll launch from.
/// - `sessions-index.json` in the same project directory is upserted so the
///   new session is searchable / nameable in Claude Code's own resume picker.
struct SessionCreator {

    struct CreatedSession {
        let sessionId: String
        let filePath: String
        let projectDirectory: String   // ~/.claude/projects/<slug>/
        let projectCwd: String         // original filesystem path (what we cd into)
    }

    enum CreationError: LocalizedError {
        case cannotDetermineCwd
        case cannotResolveProjectDirectory(String)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .cannotDetermineCwd:
                return "Cannot determine project directory for the new session."
            case .cannotResolveProjectDirectory(let path):
                return "Cannot resolve Claude project directory for \(path)."
            case .writeFailed(let e):
                return "Failed to write new session: \(e.localizedDescription)"
            }
        }
    }

    /// Create a new session file on disk.
    ///
    /// - Parameters:
    ///   - jsonl: Pre-built JSONL content (from CleanConversationService)
    ///   - sessionId: UUID for the new session (matches sessionId inside the entries)
    ///   - cwd: The original project cwd (e.g. `/Users/alice/dev/Narkis`).
    ///          The new JSONL is written to the corresponding `~/.claude/projects/<slug>/`.
    ///   - title: Human-readable title for `sessions-index.json.summary`
    ///   - firstPrompt: First user message text, for the index
    ///   - userCount + assistantCount: For the index's messageCount field
    /// - Returns: Metadata about the created session
    func create(
        jsonl: String,
        sessionId: String,
        cwd: String,
        title: String,
        firstPrompt: String?,
        userCount: Int,
        assistantCount: Int,
        gitBranch: String?
    ) throws -> CreatedSession {
        let projectDir = projectDirectory(forCwd: cwd)
        let fm = FileManager.default

        // Ensure project directory exists
        if !fm.fileExists(atPath: projectDir) {
            try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        }

        // Write JSONL atomically
        let filePath = projectDir + "/" + sessionId + ".jsonl"
        let tempPath = projectDir + "/.\(UUID().uuidString).tmp"

        do {
            try jsonl.write(toFile: tempPath, atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: filePath) {
                try fm.removeItem(atPath: filePath)
            }
            try fm.moveItem(atPath: tempPath, toPath: filePath)
        } catch {
            try? fm.removeItem(atPath: tempPath)
            throw CreationError.writeFailed(error)
        }

        // Upsert sessions-index.json entry
        let totalMessages = userCount + assistantCount
        upsertIndexEntry(
            projectDir: projectDir,
            sessionId: sessionId,
            filePath: filePath,
            title: title,
            firstPrompt: firstPrompt,
            messageCount: totalMessages,
            gitBranch: gitBranch,
            projectCwd: cwd
        )

        return CreatedSession(
            sessionId: sessionId,
            filePath: filePath,
            projectDirectory: projectDir,
            projectCwd: cwd
        )
    }

    /// Convert a filesystem cwd to Claude Code's on-disk project directory path.
    /// Example: `/Users/alice/dev/Narkis` → `~/.claude/projects/-Users-alice-dev-Narkis`
    /// Example: `/Users/alice/.hermes` → `~/.claude/projects/-Users-alice--hermes`
    ///
    /// Claude Code's slug algorithm: replace BOTH `/` and `.` with `-`.
    /// That is why `/Users/alice/.hermes` becomes `-Users-alice--hermes` (double dash from the dot).
    func projectDirectory(forCwd cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var slug = cwd
        slug = slug.replacingOccurrences(of: "/", with: "-")
        slug = slug.replacingOccurrences(of: ".", with: "-")
        return home + "/.claude/projects/" + slug
    }

    // MARK: - sessions-index.json upsert

    private func upsertIndexEntry(
        projectDir: String,
        sessionId: String,
        filePath: String,
        title: String,
        firstPrompt: String?,
        messageCount: Int,
        gitBranch: String?,
        projectCwd: String
    ) {
        let indexPath = projectDir + "/sessions-index.json"
        let fm = FileManager.default

        // Load existing index or create new
        var indexObj: [String: Any] = [:]
        var entries: [[String: Any]] = []

        if let data = fm.contents(atPath: indexPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            indexObj = parsed
            entries = (parsed["entries"] as? [[String: Any]]) ?? []
        } else {
            indexObj["version"] = 1
            indexObj["originalPath"] = projectCwd
        }

        // Remove any existing entry for this sessionId (shouldn't exist, but defensive)
        entries.removeAll { ($0["sessionId"] as? String) == sessionId }

        let now = ISO8601DateFormatter.withFractionalSeconds.string(from: Date())
        let mtime = Int64(Date().timeIntervalSince1970 * 1000)

        var entry: [String: Any] = [
            "sessionId": sessionId,
            "fullPath": filePath,
            "fileMtime": mtime,
            "summary": title,
            "messageCount": messageCount,
            "created": now,
            "modified": now,
            "gitBranch": gitBranch ?? "",
            "projectPath": projectCwd,
            "isSidechain": false
        ]
        if let fp = firstPrompt {
            entry["firstPrompt"] = fp
        }

        entries.append(entry)
        indexObj["entries"] = entries

        if let data = try? JSONSerialization.data(withJSONObject: indexObj, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: indexPath))
        }
    }

    /// Copy an existing session's JSONL into a different project, rewriting
    /// cwd + sessionId so `claude --resume` will work from the new project's
    /// working directory.
    ///
    /// - Parameters:
    ///   - sourceFilePath: Path to the source JSONL
    ///   - sourceTitle: Title of the source, used for the copied title prefix
    ///   - sourceProjectName: Human-readable name of the source project
    ///   - targetCwd: The filesystem path for the target project
    /// - Returns: Metadata about the created session
    func copyToProject(
        sourceFilePath: String,
        sourceTitle: String,
        sourceProjectName: String,
        targetCwd: String
    ) throws -> CreatedSession {
        let fm = FileManager.default
        guard let sourceData = fm.contents(atPath: sourceFilePath),
              let sourceText = String(data: sourceData, encoding: .utf8) else {
            throw CreationError.writeFailed(NSError(domain: "SessionCreator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read source file"]))
        }

        let newSessionId = UUID().uuidString.lowercased()
        var userCount = 0
        var assistantCount = 0

        // Rewrite every line: update cwd + sessionId. Leave everything else
        // (uuids, parentUuids, timestamps, tool calls, etc.) intact.
        let rewrittenLines: [String] = sourceText.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8),
                  var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return String(line) // preserve malformed
            }
            if dict["cwd"] != nil {
                dict["cwd"] = targetCwd
            }
            if dict["sessionId"] != nil {
                dict["sessionId"] = newSessionId
            }

            // Count dialogue messages for the index
            if let t = dict["type"] as? String {
                if t == "user",
                   let msg = dict["message"] as? [String: Any],
                   msg["content"] is String,
                   dict["isCompactSummary"] as? Bool != true {
                    userCount += 1
                }
                if t == "assistant" { assistantCount += 1 }
            }

            guard let newData = try? JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]),
                  let str = String(data: newData, encoding: .utf8) else {
                return nil
            }
            return str
        }

        let jsonl = rewrittenLines.joined(separator: "\n") + "\n"
        let newTitle = "moved from \(sourceProjectName) · \(sourceTitle)"

        // Grab firstPrompt + gitBranch for the new index entry
        let firstPrompt = extractFirstUserPrompt(from: jsonl)
        let gitBranch = extractGitBranch(from: jsonl)

        return try create(
            jsonl: jsonl,
            sessionId: newSessionId,
            cwd: targetCwd,
            title: newTitle,
            firstPrompt: firstPrompt,
            userCount: userCount,
            assistantCount: assistantCount,
            gitBranch: gitBranch
        )
    }

    private func extractFirstUserPrompt(from jsonl: String) -> String? {
        for line in jsonl.split(separator: "\n").prefix(50) {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  dict["type"] as? String == "user",
                  let msg = dict["message"] as? [String: Any],
                  let content = msg["content"] as? String,
                  dict["isCompactSummary"] as? Bool != true else { continue }
            return String(content.prefix(200))
        }
        return nil
    }

    private func extractGitBranch(from jsonl: String) -> String? {
        for line in jsonl.split(separator: "\n").prefix(10) {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let branch = dict["gitBranch"] as? String else { continue }
            return branch
        }
        return nil
    }

    /// Remove a session entry from `sessions-index.json`. Used after a session
    /// file has been deleted from disk — keeps the index in sync.
    func removeSessionFromIndex(projectCwd: String, sessionId: String) {
        let projectDir = projectDirectory(forCwd: projectCwd)
        let indexPath = projectDir + "/sessions-index.json"
        let fm = FileManager.default

        guard let data = fm.contents(atPath: indexPath),
              var indexObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var entries = indexObj["entries"] as? [[String: Any]] else {
            return
        }

        entries.removeAll { ($0["sessionId"] as? String) == sessionId }
        indexObj["entries"] = entries

        if let newData = try? JSONSerialization.data(withJSONObject: indexObj, options: [.prettyPrinted]) {
            try? newData.write(to: URL(fileURLWithPath: indexPath))
        }
    }

    /// Update the summary/title for an existing session.
    ///
    /// Writes through to two places so the rename actually sticks in
    /// Claude Code's UI:
    ///
    ///   1. `sessions-index.json` → `entries[].summary` (drives Claude Code's
    ///      session picker label).
    ///   2. The JSONL file itself → ensures a `{"type":"custom-title", ...}`
    ///      line exists at the top. Some Claude Code versions read this
    ///      directly when listing sessions; either way it's the canonical
    ///      record of "user gave this session a name."
    func updateSessionTitle(projectCwd: String, sessionId: String, newTitle: String) {
        let projectDir = projectDirectory(forCwd: projectCwd)
        let indexPath = projectDir + "/sessions-index.json"
        let fm = FileManager.default

        // 1. sessions-index.json
        if let data = fm.contents(atPath: indexPath),
           var indexObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var entries = indexObj["entries"] as? [[String: Any]] {
            for i in entries.indices where (entries[i]["sessionId"] as? String) == sessionId {
                entries[i]["summary"] = newTitle
                entries[i]["modified"] = ISO8601DateFormatter.withFractionalSeconds.string(from: Date())
                break
            }
            indexObj["entries"] = entries
            if let newData = try? JSONSerialization.data(withJSONObject: indexObj, options: [.prettyPrinted]) {
                try? newData.write(to: URL(fileURLWithPath: indexPath))
            }
        }

        // 2. JSONL custom-title line
        let jsonlPath = projectDir + "/" + sessionId + ".jsonl"
        upsertCustomTitleLine(jsonlPath: jsonlPath, sessionId: sessionId, title: newTitle)
    }

    /// Insert or update the `custom-title` JSONL entry at the top of the file.
    /// If a `custom-title` line already exists anywhere in the file, replace
    /// its `customTitle`. Otherwise prepend a new line.
    private func upsertCustomTitleLine(jsonlPath: String, sessionId: String, title: String) {
        guard let raw = try? String(contentsOfFile: jsonlPath, encoding: .utf8) else { return }

        let titleEntry: [String: Any] = [
            "type": "custom-title",
            "customTitle": title,
            "sessionId": sessionId
        ]
        guard let titleData = try? JSONSerialization.data(withJSONObject: titleEntry,
                                                          options: [.withoutEscapingSlashes]),
              let titleLine = String(data: titleData, encoding: .utf8) else { return }

        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var replaced = false
        for i in lines.indices {
            // Cheap detection — avoids decoding every line
            if lines[i].contains("\"type\":\"custom-title\"")
                || lines[i].contains("\"type\": \"custom-title\"") {
                lines[i] = titleLine
                replaced = true
                break
            }
        }
        if !replaced {
            lines.insert(titleLine, at: 0)
        }

        let output = lines.joined(separator: "\n")
        try? output.write(toFile: jsonlPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - ISO8601 helper

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
