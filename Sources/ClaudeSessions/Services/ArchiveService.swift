import Foundation

/// Physically moves session JSONL files out of `~/.claude/projects/` and into
/// `~/.claude-sessions-archive/<projectId>/<sessionId>.jsonl`, with a companion
/// `.meta.json` that records the original location so we can restore.
///
/// Claude Code only sees files in `~/.claude/projects/`, so archived sessions
/// disappear from its resume picker too. Restoring moves the file back.
///
/// This is distinct from HiddenStore (which is purely visual).
struct ArchiveService {

    struct ArchivedEntry: Identifiable, Equatable {
        let sessionId: String
        let title: String
        let originalPath: String           // the full JSONL path where it came from
        let originalProjectPath: String    // cwd of the original project (e.g. /Users/sauel/dev/foo)
        let originalProjectName: String    // human-readable project name at archive time
        let archivedPath: String           // current file path in the archive
        let archivedAt: Date
        let messageCount: Int

        var id: String { sessionId }
    }

    enum ArchiveError: LocalizedError {
        case sourceMissing(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let p): return "Source file missing: \(p)"
            case .writeFailed(let s):   return "Archive failed: \(s)"
            }
        }
    }

    private let archiveRoot: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        archiveRoot = home + "/.claude-sessions-archive"
    }

    // MARK: - Archive

    func archive(session: SessionInfo, projectId: String, projectName: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: session.filePath) else {
            throw ArchiveError.sourceMissing(session.filePath)
        }

        let projectDir = archiveRoot + "/" + projectId
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        let archivedPath = projectDir + "/" + session.id + ".jsonl"
        let metaPath     = projectDir + "/" + session.id + ".meta.json"

        do {
            if fm.fileExists(atPath: archivedPath) {
                try fm.removeItem(atPath: archivedPath)
            }
            try fm.moveItem(atPath: session.filePath, toPath: archivedPath)

            let meta: [String: Any] = [
                "sessionId": session.id,
                "title": session.title,
                "originalPath": session.filePath,
                "originalProjectPath": session.projectPath ?? "",
                "originalProjectName": projectName,
                "archivedAt": ISO8601DateFormatter.withFractionalSeconds.string(from: Date()),
                "messageCount": session.messageCount
            ]
            let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: metaPath))
        } catch {
            throw ArchiveError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    func restore(entry: ArchivedEntry) throws {
        let fm = FileManager.default
        let destDir = (entry.originalPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: entry.originalPath) {
            // Original path is taken — fall back to a unique suffix
            let unique = destDir + "/" + entry.sessionId + "-restored.jsonl"
            try fm.moveItem(atPath: entry.archivedPath, toPath: unique)
        } else {
            try fm.moveItem(atPath: entry.archivedPath, toPath: entry.originalPath)
        }

        // Drop the meta file
        let metaPath = metaPath(for: entry)
        if fm.fileExists(atPath: metaPath) {
            try? fm.removeItem(atPath: metaPath)
        }
    }

    // MARK: - Permanent delete

    func permanentlyDelete(entry: ArchivedEntry) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: entry.archivedPath) {
            try fm.removeItem(atPath: entry.archivedPath)
        }
        let metaPath = metaPath(for: entry)
        if fm.fileExists(atPath: metaPath) {
            try? fm.removeItem(atPath: metaPath)
        }
    }

    // MARK: - List

    func listArchived() -> [ArchivedEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveRoot),
              let projectDirs = try? fm.contentsOfDirectory(atPath: archiveRoot) else {
            return []
        }

        let formatter = ISO8601DateFormatter.withFractionalSeconds
        var out: [ArchivedEntry] = []

        for projectDir in projectDirs {
            let fullDir = archiveRoot + "/" + projectDir
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullDir, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: fullDir) else { continue }

            for file in files where file.hasSuffix(".meta.json") {
                let metaPath = fullDir + "/" + file
                guard let data = fm.contents(atPath: metaPath),
                      let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessionId = meta["sessionId"] as? String
                else { continue }

                let archivedPath = fullDir + "/" + sessionId + ".jsonl"
                guard fm.fileExists(atPath: archivedPath) else { continue }

                let archivedAt = (meta["archivedAt"] as? String).flatMap { formatter.date(from: $0) } ?? Date()

                out.append(ArchivedEntry(
                    sessionId: sessionId,
                    title: (meta["title"] as? String) ?? "Untitled",
                    originalPath: (meta["originalPath"] as? String) ?? "",
                    originalProjectPath: (meta["originalProjectPath"] as? String) ?? "",
                    originalProjectName: (meta["originalProjectName"] as? String) ?? "unknown",
                    archivedPath: archivedPath,
                    archivedAt: archivedAt,
                    messageCount: (meta["messageCount"] as? Int) ?? 0
                ))
            }
        }

        return out.sorted { $0.archivedAt > $1.archivedAt }
    }

    // MARK: - Helpers

    private func metaPath(for entry: ArchivedEntry) -> String {
        let dir = (entry.archivedPath as NSString).deletingLastPathComponent
        return dir + "/" + entry.sessionId + ".meta.json"
    }
}
