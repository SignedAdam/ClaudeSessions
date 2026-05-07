import Foundation

/// Restore a version into the source project as a fresh resumable session.
///
/// The original version file is never modified. We read its JSONL, rewrite
/// the `sessionId` field on every entry to a new UUID, and write the
/// result to `~/.claude/projects/<slug>/<newSessionId>.jsonl`. The new
/// session is registered in `sessions-index.json` so it shows up in
/// Claude Code's resume picker.
///
/// Different from `BackupVaultService.restore` (which keeps the original
/// sessionId and refuses to overwrite). This always creates a NEW id, so
/// the restored copy can coexist with the live original — useful when the
/// user wants to compare them or branch from a known-good past state.
struct VersionRestoreService {

    enum RestoreError: LocalizedError {
        case sourceUnreadable(String)
        case noProjectCwd
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .sourceUnreadable(let p): return "Could not read version file: \(p)"
            case .noProjectCwd:            return "Cannot determine target project directory."
            case .writeFailed(let e):      return "Restore failed: \(e.localizedDescription)"
            }
        }
    }

    struct Restored {
        let newSessionId: String
        let filePath: String
        let title: String
    }

    private let sessionCreator = SessionCreator()

    /// Restore `version` into `projectCwd` as a fresh session.
    /// `originalTitle` is the live session's title used as the prefix.
    func restore(
        version: VersionHistoryService.Version,
        projectCwd: String,
        originalTitle: String
    ) throws -> Restored {
        let fm = FileManager.default
        guard let sourceData = fm.contents(atPath: version.filePath) else {
            throw RestoreError.sourceUnreadable(version.filePath)
        }
        guard let sourceText = String(data: sourceData, encoding: .utf8) else {
            throw RestoreError.sourceUnreadable(version.filePath)
        }

        let newSessionId = UUID().uuidString.lowercased()
        let rewritten = rewriteSessionId(jsonl: sourceText, newSessionId: newSessionId)

        let title = "\(originalTitle) · restored from \(formatTimestamp(version.timestamp))"

        // Walk the rewritten JSONL once to count user/assistant entries
        // for the index's messageCount, and to find a firstPrompt.
        let stats = countMessages(jsonl: rewritten)

        do {
            let created = try sessionCreator.create(
                jsonl: rewritten,
                sessionId: newSessionId,
                cwd: projectCwd,
                title: title,
                firstPrompt: stats.firstPrompt,
                userCount: stats.userCount,
                assistantCount: stats.assistantCount,
                gitBranch: nil
            )
            return Restored(newSessionId: created.sessionId,
                            filePath: created.filePath,
                            title: title)
        } catch {
            throw RestoreError.writeFailed(error)
        }
    }

    // MARK: - JSONL rewrite

    /// Replace the top-level `"sessionId"` value on every line.
    /// Per-entry `uuid`/`parentUuid` are preserved — the parent chain is
    /// already valid within the file and re-using uuids across the new
    /// session is fine because the new sessionId scopes them.
    private func rewriteSessionId(jsonl: String, newSessionId: String) -> String {
        var out: [String] = []
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                out.append(String(line))
                continue
            }
            // Only rewrite if the field exists; skip pure metadata lines
            // that don't reference a session.
            if dict["sessionId"] != nil {
                dict["sessionId"] = newSessionId
            }
            // Per `custom-title` line shape (cycle 22 / rename feature),
            // those carry their own sessionId — overwrite there too.
            if (dict["type"] as? String) == "custom-title" {
                dict["sessionId"] = newSessionId
            }
            if let serialized = try? JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]),
               let str = String(data: serialized, encoding: .utf8) {
                out.append(str)
            } else {
                out.append(String(line))
            }
        }
        return out.joined(separator: "\n") + (jsonl.hasSuffix("\n") ? "\n" : "")
    }

    // MARK: - Stats

    private struct Stats {
        let userCount: Int
        let assistantCount: Int
        let firstPrompt: String?
    }

    private func countMessages(jsonl: String) -> Stats {
        var userCount = 0
        var assistantCount = 0
        var firstPrompt: String?
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = dict["type"] as? String
            if type == "user" {
                userCount += 1
                if firstPrompt == nil,
                   let msg = dict["message"] as? [String: Any],
                   let content = msg["content"] as? String,
                   !content.isEmpty {
                    firstPrompt = String(content.prefix(200))
                }
            } else if type == "assistant" {
                assistantCount += 1
            }
        }
        return Stats(userCount: userCount, assistantCount: assistantCount, firstPrompt: firstPrompt)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f.string(from: date)
    }
}
