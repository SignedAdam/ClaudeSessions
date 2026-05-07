import Foundation
import ContinuousBackup

/// Aggregates every previous version of a session that exists on disk.
///
/// Versions live in four places (audited in cycle 54 / P7.T01), all keyed
/// by `sessionId`:
///
/// 1. `.live`           — `~/.claude/projects/<slug>/<sessionId>.jsonl`
/// 2. `.saveBackup`     — `~/.claude-sessions-backups/<sessionId>/<HH-mm-ss>.jsonl`
/// 3. `.vaultLive`      — `~/.ClaudeSessions/backup/projects/<slug>/<sessionId>.jsonl`
/// 4. `.vaultSnapshot`  — `…/<sessionId>.jsonl.orig-<unix-ts>`
/// 5. `.archive`        — `~/.claude-sessions-archive/<projectId>/<sessionId>.jsonl`
///
/// Filesystem-based — doesn't depend on the BackupEngine manifest, so it
/// keeps working if the manifest is corrupt or missing.
enum VersionHistoryService {

    enum SourceKind: String, CaseIterable {
        case live           // ~/.claude/projects/.../<id>.jsonl
        case saveBackup     // ~/.claude-sessions-backups/<id>/<ts>.jsonl
        case vaultLive      // ~/.ClaudeSessions/backup/projects/.../<id>.jsonl
        case vaultSnapshot  // …/<id>.jsonl.orig-<ts>
        case archive        // ~/.claude-sessions-archive/<projectId>/<id>.jsonl

        var label: String {
            switch self {
            case .live:          return "live"
            case .saveBackup:    return "save backup"
            case .vaultLive:     return "vault mirror"
            case .vaultSnapshot: return "vault snapshot"
            case .archive:       return "archived"
            }
        }
    }

    struct Version: Identifiable, Hashable {
        let id: String        // unique key — the file path
        let sessionId: String
        let kind: SourceKind
        let filePath: String
        let timestamp: Date   // when this version came into being
        let size: Int64
        let isCurrent: Bool   // true for `.live`
    }

    // MARK: - Listing

    /// All versions for a sessionId. `projectSlug` is required to find
    /// `.live` and `.vault*` entries (those are organized by project).
    /// Pass nil if the session lives in archive only — those still work.
    /// Returned sorted: live → save backups (newest first) → vault snapshots
    /// (newest first) → archive.
    static func versions(forSessionId id: String, projectSlug: String?) -> [Version] {
        var out: [Version] = []
        out.append(contentsOf: liveVersions(id: id, projectSlug: projectSlug))
        out.append(contentsOf: saveBackupVersions(id: id))
        out.append(contentsOf: vaultVersions(id: id, projectSlug: projectSlug))
        out.append(contentsOf: archiveVersions(id: id))
        return out.sorted(by: orderingPriority)
    }

    /// Stable sort: live first, then by source-kind priority, then newest first.
    private static func orderingPriority(_ lhs: Version, _ rhs: Version) -> Bool {
        if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
        let priority: [SourceKind: Int] = [
            .live: 0, .saveBackup: 1, .vaultLive: 2, .vaultSnapshot: 2, .archive: 3
        ]
        let lp = priority[lhs.kind] ?? 99
        let rp = priority[rhs.kind] ?? 99
        if lp != rp { return lp < rp }
        return lhs.timestamp > rhs.timestamp
    }

    // MARK: - Source: live

    private static func liveVersions(id: String, projectSlug: String?) -> [Version] {
        guard let slug = projectSlug else { return [] }
        let path = "\(NSHomeDirectory())/.claude/projects/\(slug)/\(id).jsonl"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return [] }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date) ?? Date()
        return [Version(id: path, sessionId: id, kind: .live, filePath: path,
                        timestamp: mtime, size: size, isCurrent: true)]
    }

    // MARK: - Source: save backups

    private static let saveBackupRoot: String = "\(NSHomeDirectory())/.claude-sessions-backups"

    private static let saveBackupTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f
    }()

    private static func saveBackupVersions(id: String) -> [Version] {
        let dir = saveBackupRoot + "/" + id
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files.compactMap { name -> Version? in
            guard name.hasSuffix(".jsonl") else { return nil }
            let path = dir + "/" + name
            let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let stamp = String(name.dropLast(6))  // strip .jsonl
            let parsedTimestamp = saveBackupTimestampFormatter.date(from: stamp)
                ?? (attrs[.modificationDate] as? Date)
                ?? Date.distantPast
            return Version(id: path, sessionId: id, kind: .saveBackup, filePath: path,
                           timestamp: parsedTimestamp, size: size, isCurrent: false)
        }
    }

    // MARK: - Source: BackupEngine vault

    private static func vaultVersions(id: String, projectSlug: String?) -> [Version] {
        guard let slug = projectSlug else { return [] }
        let dir = BackupEngine.backupMirrorRoot.path + "/" + slug
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        var out: [Version] = []
        let livePrefix = "\(id).jsonl"
        for file in files {
            // Match files for this sessionId only.
            guard file.hasPrefix(livePrefix) else { continue }
            let path = dir + "/" + file
            let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date) ?? Date()

            if file == livePrefix {
                out.append(Version(id: path, sessionId: id, kind: .vaultLive,
                                   filePath: path, timestamp: mtime, size: size, isCurrent: false))
            } else if let range = file.range(of: ".jsonl.orig-") {
                let tsString = String(file[range.upperBound...])
                let ts = Double(tsString).map { Date(timeIntervalSince1970: $0) } ?? mtime
                out.append(Version(id: path, sessionId: id, kind: .vaultSnapshot,
                                   filePath: path, timestamp: ts, size: size, isCurrent: false))
            }
        }
        return out
    }

    // MARK: - Source: archive

    private static func archiveVersions(id: String) -> [Version] {
        let archive = ArchiveService()
        let entries = archive.listArchived().filter { $0.sessionId == id }
        return entries.map { entry in
            let attrs = (try? FileManager.default.attributesOfItem(atPath: entry.archivedPath)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            return Version(id: entry.archivedPath, sessionId: id, kind: .archive,
                           filePath: entry.archivedPath, timestamp: entry.archivedAt,
                           size: size, isCurrent: false)
        }
    }
}
