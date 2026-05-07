import Foundation
import ContinuousBackup

/// Reads the on-disk backup mirror at `~/.ClaudeSessions/backup/projects/`
/// and exposes it as a list of restorable entries.
///
/// Filesystem-based (no manifest needed). This makes the vault usable even
/// if the manifest got corrupted or the backup daemon hasn't run yet.
enum BackupVaultService {

    /// One restorable backup file. May be the live mirror copy or a
    /// rotated `.orig-<unix-ts>` snapshot.
    struct Entry: Identifiable, Hashable {
        let id: String                  // path on disk
        let projectSlug: String         // "-Users-alice-dev-Foo"
        let sessionId: String           // UUID-or-other base name
        let isSnapshot: Bool            // true for .orig-* files
        let snapshotTimestamp: Date?    // parsed from the .orig-<ts> suffix
        let backupPath: String
        let size: Int64
        let modifiedAt: Date
        let sourceExists: Bool          // does ~/.claude/projects/<slug>/<id>.jsonl still exist?
    }

    enum RestoreError: Error, LocalizedError {
        case backupMissing(String)
        case targetExists(String)
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .backupMissing(let p):
                return "Backup not found at \(p)."
            case .targetExists(let p):
                return "A file already exists at \(p). Restore aborted to avoid overwriting."
            case .copyFailed(let err):
                return "Restore copy failed: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Listing

    /// Walk the backup mirror and produce one Entry per file. Sorted with
    /// orphaned-source entries first (those are the ones the user most
    /// likely wants to restore), then by modifiedAt descending.
    static func listEntries() -> [Entry] {
        let fm = FileManager.default
        let root = BackupEngine.backupMirrorRoot.path
        guard fm.fileExists(atPath: root) else { return [] }

        var entries: [Entry] = []
        // Two-level walk: <slug>/<file>
        guard let slugs = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        for slug in slugs where !slug.hasPrefix(".") {
            let slugPath = root + "/" + slug
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: slugPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let files = try? fm.contentsOfDirectory(atPath: slugPath) else { continue }
            for file in files {
                let backupPath = slugPath + "/" + file
                guard let attrs = try? fm.attributesOfItem(atPath: backupPath) else { continue }
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast

                let parsed = parseFile(file)
                let sourcePath = "\(BackupEngine.sourceRoot)/\(slug)/\(parsed.sessionId).jsonl"
                let sourceExists = fm.fileExists(atPath: sourcePath)

                entries.append(Entry(
                    id: backupPath,
                    projectSlug: slug,
                    sessionId: parsed.sessionId,
                    isSnapshot: parsed.isSnapshot,
                    snapshotTimestamp: parsed.timestamp,
                    backupPath: backupPath,
                    size: size,
                    modifiedAt: mtime,
                    sourceExists: sourceExists
                ))
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.sourceExists != rhs.sourceExists {
                // Missing-source entries first (more likely targets for restore)
                return !lhs.sourceExists && rhs.sourceExists
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    /// Group entries by their (projectSlug, sessionId) key. Keys for
    /// snapshots collapse onto the same group as their live entry.
    static func groupBySession(_ entries: [Entry]) -> [(String, String, [Entry])] {
        let grouped = Dictionary(grouping: entries) { "\($0.projectSlug)|\($0.sessionId)" }
        return grouped.map { (key, items) in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return (parts[0], parts[1], items.sorted { $0.modifiedAt > $1.modifiedAt })
        }
        .sorted { ($0.2.first?.modifiedAt ?? .distantPast) > ($1.2.first?.modifiedAt ?? .distantPast) }
    }

    // MARK: - Restore

    /// Copy a backup file back into `~/.claude/projects/<slug>/<sessionId>.jsonl`.
    ///
    /// Refuses to overwrite an existing file (caller decides what to do
    /// when the source still exists — typically prompts the user). The
    /// session won't appear in `claude --resume <id>` until Claude Code's
    /// next process restart re-scans the project directory.
    @discardableResult
    static func restore(entry: Entry, asSessionId targetId: String? = nil) throws -> URL {
        let fm = FileManager.default
        let id = targetId ?? entry.sessionId
        let projectDir = "\(BackupEngine.sourceRoot)/\(entry.projectSlug)"
        let targetPath = "\(projectDir)/\(id).jsonl"

        guard fm.fileExists(atPath: entry.backupPath) else {
            throw RestoreError.backupMissing(entry.backupPath)
        }
        if fm.fileExists(atPath: targetPath) {
            throw RestoreError.targetExists(targetPath)
        }

        do {
            try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            try fm.copyItem(atPath: entry.backupPath, toPath: targetPath)
        } catch {
            throw RestoreError.copyFailed(error)
        }

        return URL(fileURLWithPath: targetPath)
    }

    // MARK: - Filename parsing

    private struct ParsedName {
        let sessionId: String
        let isSnapshot: Bool
        let timestamp: Date?
    }

    /// Backup files come in two shapes:
    ///   <session-id>.jsonl          — the live mirror
    ///   <session-id>.jsonl.orig-<unix-ts>  — a rotated snapshot
    private static func parseFile(_ name: String) -> ParsedName {
        // Strip ".jsonl" or ".jsonl.orig-<ts>"
        if let range = name.range(of: ".jsonl.orig-") {
            let id = String(name[..<range.lowerBound])
            let tsString = String(name[range.upperBound...])
            let ts = Double(tsString).map { Date(timeIntervalSince1970: $0) }
            return ParsedName(sessionId: id, isSnapshot: true, timestamp: ts)
        }
        if name.hasSuffix(".jsonl") {
            return ParsedName(sessionId: String(name.dropLast(6)),
                              isSnapshot: false,
                              timestamp: nil)
        }
        return ParsedName(sessionId: name, isSnapshot: false, timestamp: nil)
    }
}
