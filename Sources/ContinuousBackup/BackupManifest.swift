import Foundation

/// In-memory + on-disk manifest tracking every file we've mirrored into the
/// backup. Keyed by absolute source path. Atomic rewrite on flush.
///
/// All mutation goes through the serial `queue` below — callers MAY be on any
/// thread. Reads (`lookup`, `stats`, `allEntries`) return a snapshot and are
/// also serialized.
///
/// Corruption safety: atomic write via tmp-file + rename. If the JSON fails to
/// decode on load, we start fresh and log — losing the manifest only triggers
/// a rebootstrap scan (full re-check of sizes/mtimes), not data loss.
final class BackupManifest {

    // MARK: - Types

    struct FileState: Codable, Equatable {
        var sourcePath: String
        var backupPath: String
        var lastSize: Int64
        var lastMtime: Double
        var sourceExists: Bool
        var lastSyncAt: Double
        var firstBackedUpAt: Double
        var deleteDetectedAt: Double?
        /// First line of the source JSONL, truncated to ~1KB. Used to detect
        /// whole-file rewrites that happen to leave the size growing (e.g.
        /// the file got deleted by `cleanupPeriodDays` and re-created with
        /// different content but a similar shape). Optional so manifests
        /// from older versions still decode cleanly.
        var firstLineSignature: String?
    }

    struct Stats {
        var trackedFiles: Int
        var livingSourceFiles: Int
        var orphanedBackupFiles: Int   // source_exists == false
        var totalBackupBytes: Int64
    }

    // MARK: - Storage

    private let dbURL: URL
    private var states: [String: FileState] = [:]
    private var dirty: Bool = false
    private let queue = DispatchQueue(label: "claude-sessions.backup.manifest", qos: .utility)

    // MARK: - Init

    init(dbURL: URL) {
        self.dbURL = dbURL
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return }
        do {
            let data = try Data(contentsOf: dbURL)
            let decoded = try JSONDecoder().decode([FileState].self, from: data)
            states = Dictionary(uniqueKeysWithValues: decoded.map { ($0.sourcePath, $0) })
        } catch {
            // Corrupt / unreadable manifest: start fresh. Data is not lost —
            // backup files remain; we'll just re-stat sources on next walk.
            NSLog("[BackupManifest] failed to load manifest, starting fresh: \(error)")
            states = [:]
        }
    }

    // MARK: - Reads

    func lookup(sourcePath: String) -> FileState? {
        queue.sync { states[sourcePath] }
    }

    func allEntries() -> [FileState] {
        queue.sync { Array(states.values) }
    }

    func stats() -> Stats {
        queue.sync {
            var trackedFiles = 0
            var living = 0
            var orphaned = 0
            var totalBytes: Int64 = 0
            for s in states.values {
                trackedFiles += 1
                if s.sourceExists { living += 1 } else { orphaned += 1 }
                totalBytes += s.lastSize
            }
            return Stats(
                trackedFiles: trackedFiles,
                livingSourceFiles: living,
                orphanedBackupFiles: orphaned,
                totalBackupBytes: totalBytes
            )
        }
    }

    // MARK: - Writes

    func upsert(_ state: FileState) {
        queue.sync {
            states[state.sourcePath] = state
            dirty = true
        }
    }

    func markSourceMissing(sourcePath: String, at detectedAt: Double) {
        queue.sync {
            guard var existing = states[sourcePath], existing.sourceExists else { return }
            existing.sourceExists = false
            existing.deleteDetectedAt = detectedAt
            existing.lastSyncAt = detectedAt
            states[sourcePath] = existing
            dirty = true
        }
    }

    /// Flush pending changes to disk. Atomic via tmp-file + rename.
    func flushIfDirty() {
        queue.sync {
            guard dirty else { return }
            do {
                let values = Array(states.values)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(values)

                try FileManager.default.createDirectory(
                    at: dbURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let tmp = dbURL.appendingPathExtension("tmp")
                try data.write(to: tmp, options: [.atomic])
                _ = try? FileManager.default.replaceItemAt(dbURL, withItemAt: tmp)
                dirty = false
            } catch {
                NSLog("[BackupManifest] flush failed: \(error)")
            }
        }
    }
}
