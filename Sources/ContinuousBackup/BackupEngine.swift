import Foundation
import Combine

/// Continuously mirrors `~/.claude/projects/` into `~/.ClaudeSessions/backup/projects/`.
///
/// Algorithm per file:
/// - `size == last_size && mtime == last_mtime`  → skip (HOT PATH — the whole point)
/// - new (no manifest entry)                      → full copy + insert
/// - `size > last_size`                           → append delta (read from last_size → EOF, append)
/// - `size < last_size` (truncation / rotation)   → rename backup to `.orig-<ts>`, full re-copy
/// - source missing but manifest has it           → mark source_exists=0, keep backup
/// - source returns after missing                 → full copy, flip source_exists back
///
/// Claude Code's `cleanupPeriodDays` cannot propagate into backup because we
/// never delete from the backup tree. Period.
///
/// Threading: the class itself is not @MainActor. All @Published property
/// mutations are marshaled back to the main actor via `updateState` /
/// `refreshStatsAsync`. Heavy work (copy / walk) runs on `syncQueue`.
public final class BackupEngine: ObservableObject {

    // MARK: - Public observable state

    @Published public var isRunning: Bool = false
    @Published public var lastSyncAt: Date?
    @Published public var trackedFiles: Int = 0
    @Published public var livingSourceFiles: Int = 0
    @Published public var orphanedBackupFiles: Int = 0
    @Published public var totalBackupBytes: Int64 = 0
    @Published public var lowDiskSpace: Bool = false
    @Published public var lastError: String?
    @Published public var isBootstrapping: Bool = false

    // MARK: - Paths

    public static let sourceRoot: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/projects"
    }()

    public static let backupHome: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ClaudeSessions")
    }()

    public static let backupMirrorRoot: URL = backupHome.appendingPathComponent("backup/projects")
    public static let manifestURL: URL = backupHome.appendingPathComponent("manifest.json")
    public static let logURL: URL = backupHome.appendingPathComponent("sync.log")

    // MARK: - Components

    private let manifest: BackupManifest
    private let watcher = DirectoryTreeWatcher()
    private let syncQueue = DispatchQueue(label: "claude-sessions.backup.engine", qos: .utility)
    private let fm = FileManager.default

    /// File extensions/names we actually want to mirror. Everything else under
    /// `~/.claude/projects/` (`.DS_Store`, `.md` scratch files, etc.) is skipped.
    private let mirroredSuffixes: [String] = [".jsonl", ".json"]

    /// Skip any path containing a segment starting with `.` — we don't want to
    /// mirror Finder metadata or hidden dirs.
    private let skipDotfiles = true

    /// Free-disk-space floor on the backup volume. Below this, we pause sync
    /// rather than risk filling the disk.
    private let freeSpaceFloorBytes: Int64 = 1_000_000_000   // 1 GB

    /// Bootstrap throttle — sleep briefly between files so a cold launch
    /// doesn't hammer the disk.
    private let bootstrapThrottle: TimeInterval = 0.0005

    // Flush cadence
    private var flushTimer: DispatchSourceTimer?

    public init() {
        try? FileManager.default.createDirectory(at: BackupEngine.backupHome, withIntermediateDirectories: true)
        self.manifest = BackupManifest(dbURL: BackupEngine.manifestURL)
        refreshStatsSync()
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        try? fm.createDirectory(at: BackupEngine.backupMirrorRoot, withIntermediateDirectories: true)

        watcher.onBatch = { [weak self] paths in
            guard let self else { return }
            self.syncQueue.async {
                self.handleWatcherBatch(paths: paths)
            }
        }
        watcher.start(paths: [BackupEngine.sourceRoot])

        // Periodic flush of the manifest (protects against app crashes).
        let timer = DispatchSource.makeTimerSource(queue: syncQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.manifest.flushIfDirty()
        }
        timer.resume()
        flushTimer = timer

        isRunning = true
        log("engine started")

        // Kick off bootstrap scan in the background.
        isBootstrapping = true
        syncQueue.async { [weak self] in
            self?.bootstrap()
        }
    }

    public func stop() {
        guard isRunning else { return }
        watcher.stop()
        flushTimer?.cancel()
        flushTimer = nil
        manifest.flushIfDirty()
        isRunning = false
        log("engine stopped")
    }

    // MARK: - Bootstrap walk

    private func bootstrap() {
        let srcRoot = BackupEngine.sourceRoot
        guard fm.fileExists(atPath: srcRoot) else {
            updateState { $0.isBootstrapping = false }
            return
        }

        let rootURL = URL(fileURLWithPath: srcRoot)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            updateState { $0.isBootstrapping = false }
            return
        }

        log("bootstrap scan started at \(srcRoot)")
        var scanned = 0

        for case let url as URL in enumerator {
            guard shouldMirror(absolutePath: url.path) else { continue }
            let resource = try? url.resourceValues(forKeys: Set(keys))
            guard resource?.isRegularFile == true else { continue }
            syncFile(srcPath: url.path)
            scanned += 1
            if bootstrapThrottle > 0 {
                Thread.sleep(forTimeInterval: bootstrapThrottle)
            }
        }

        // Second pass: any manifest entry whose source no longer exists but we
        // still think does → mark missing. This keeps stats honest without
        // waiting for a specific FSEvent.
        for entry in manifest.allEntries() where entry.sourceExists {
            if !fm.fileExists(atPath: entry.sourcePath) {
                manifest.markSourceMissing(sourcePath: entry.sourcePath, at: Date().timeIntervalSince1970)
            }
        }

        manifest.flushIfDirty()
        log("bootstrap scan done, scanned=\(scanned)")
        refreshStatsAsync()
        updateState { $0.isBootstrapping = false }
    }

    // MARK: - Watcher batch

    private func handleWatcherBatch(paths: Set<String>) {
        for path in paths {
            handleEventPath(path)
        }
        refreshStatsAsync()
    }

    /// An FSEvent path may be either a file or a directory. Handle both.
    private func handleEventPath(_ path: String) {
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        if exists && isDir.boolValue {
            // Enumerate only the immediate children; deeper nested events will
            // arrive as their own FSEvent paths because we use kFSEventStreamCreateFlagFileEvents.
            if let contents = try? fm.contentsOfDirectory(atPath: path) {
                for child in contents {
                    let full = path + "/" + child
                    var childIsDir: ObjCBool = false
                    let childExists = fm.fileExists(atPath: full, isDirectory: &childIsDir)
                    if childExists && !childIsDir.boolValue && shouldMirror(absolutePath: full) {
                        syncFile(srcPath: full)
                    }
                }
            }
        } else if exists {
            // It's a regular file (or vanished right after we checked — syncFile handles that).
            if shouldMirror(absolutePath: path) {
                syncFile(srcPath: path)
            }
        } else {
            // Path no longer exists: look up in manifest and mark missing.
            if manifest.lookup(sourcePath: path) != nil {
                manifest.markSourceMissing(sourcePath: path, at: Date().timeIntervalSince1970)
                log("source-missing \(path)")
            }
        }
    }

    // MARK: - Filtering

    private func shouldMirror(absolutePath: String) -> Bool {
        guard absolutePath.hasPrefix(BackupEngine.sourceRoot) else { return false }
        let ext = "." + (absolutePath as NSString).pathExtension
        guard mirroredSuffixes.contains(ext) else { return false }

        if skipDotfiles {
            let relative = String(absolutePath.dropFirst(BackupEngine.sourceRoot.count))
            for segment in relative.split(separator: "/") {
                if segment.hasPrefix(".") { return false }
            }
        }
        return true
    }

    // MARK: - Core: syncFile

    private func syncFile(srcPath: String) {
        let (exists, size, mtime) = stat(path: srcPath)

        // Manifest lookup
        let existing = manifest.lookup(sourcePath: srcPath)

        guard exists else {
            if let e = existing, e.sourceExists {
                manifest.markSourceMissing(sourcePath: srcPath, at: Date().timeIntervalSince1970)
                log("source-missing \(srcPath)")
            }
            return
        }

        // Free-space guard (before any write)
        if !ensureFreeSpace() {
            return
        }

        let backupPath = computeBackupPath(forSource: srcPath)

        // Hot path: nothing changed
        if let e = existing, e.sourceExists,
           e.lastSize == size, abs(e.lastMtime - mtime) < 0.0001 {
            return
        }

        // Ensure parent dir
        let parentDir = (backupPath as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        } catch {
            log("mkdir-failed \(parentDir): \(error)")
            updateState { $0.lastError = "mkdir failed: \(parentDir)" }
            return
        }

        let now = Date().timeIntervalSince1970
        let firstBackedUp = existing?.firstBackedUpAt ?? now
        // Read once — used to detect whole-file rewrites that would otherwise
        // pass as a normal "size grew" append.
        let currentSignature = readFirstLineSignature(srcPath: srcPath)

        // Case A: no existing manifest entry → full copy
        guard let e = existing else {
            if performFullCopy(src: srcPath, dst: backupPath) {
                let state = BackupManifest.FileState(
                    sourcePath: srcPath,
                    backupPath: backupPath,
                    lastSize: size,
                    lastMtime: mtime,
                    sourceExists: true,
                    lastSyncAt: now,
                    firstBackedUpAt: firstBackedUp,
                    deleteDetectedAt: nil,
                    firstLineSignature: currentSignature
                )
                manifest.upsert(state)
                log("initial-copy \(srcPath) (\(size)B)")
            }
            return
        }

        // Case B: source was previously marked missing — treat as new
        if !e.sourceExists {
            if performFullCopy(src: srcPath, dst: backupPath) {
                var revived = e
                revived.backupPath = backupPath
                revived.lastSize = size
                revived.lastMtime = mtime
                revived.sourceExists = true
                revived.lastSyncAt = now
                revived.deleteDetectedAt = nil
                revived.firstLineSignature = currentSignature
                manifest.upsert(revived)
                log("revived \(srcPath)")
            }
            return
        }

        // First-line check: if the manifest has a recorded signature and it
        // disagrees with what's on disk, the file was rewritten regardless of
        // size direction. Rotate the old backup as a versioned snapshot and
        // re-copy from scratch.
        let signatureChanged = (e.firstLineSignature != nil)
            && (currentSignature != e.firstLineSignature)
        if signatureChanged {
            let ts = Int(now)
            let rotated = backupPath + ".orig-\(ts)"
            _ = try? fm.moveItem(atPath: backupPath, toPath: rotated)
            if performFullCopy(src: srcPath, dst: backupPath) {
                var updated = e
                updated.lastSize = size
                updated.lastMtime = mtime
                updated.lastSyncAt = now
                updated.firstLineSignature = currentSignature
                manifest.upsert(updated)
                log("rewrite-detected \(srcPath) (kept \(rotated))")
            }
            return
        }

        // Case C: source grew → append delta
        if size > e.lastSize {
            if performAppendDelta(src: srcPath, dst: backupPath, from: e.lastSize, to: size) {
                var updated = e
                updated.lastSize = size
                updated.lastMtime = mtime
                updated.lastSyncAt = now
                // Persist the signature even if it was previously nil so we can
                // detect future rewrites.
                if updated.firstLineSignature == nil {
                    updated.firstLineSignature = currentSignature
                }
                manifest.upsert(updated)
                log("append \(srcPath) +\(size - e.lastSize)B")
            }
            return
        }

        // Case D: source shrank → rename old backup, full re-copy
        if size < e.lastSize {
            let ts = Int(now)
            let rotated = backupPath + ".orig-\(ts)"
            _ = try? fm.moveItem(atPath: backupPath, toPath: rotated)
            if performFullCopy(src: srcPath, dst: backupPath) {
                var updated = e
                updated.lastSize = size
                updated.lastMtime = mtime
                updated.lastSyncAt = now
                updated.firstLineSignature = currentSignature
                manifest.upsert(updated)
                log("truncate-recopy \(srcPath) (kept \(rotated))")
            }
            return
        }

        // Case E: size same, mtime changed → in-place rewrite (rare for jsonl).
        // We always full-copy here. Rotate the old backup so the prior version
        // is preserved as a versioned snapshot.
        let ts = Int(now)
        let rotated = backupPath + ".orig-\(ts)"
        _ = try? fm.moveItem(atPath: backupPath, toPath: rotated)
        if performFullCopy(src: srcPath, dst: backupPath) {
            var updated = e
            updated.lastMtime = mtime
            updated.lastSyncAt = now
            updated.firstLineSignature = currentSignature
            manifest.upsert(updated)
            log("rewrite \(srcPath)")
        }
    }

    // MARK: - Copy primitives

    private func performFullCopy(src: String, dst: String) -> Bool {
        do {
            if fm.fileExists(atPath: dst) {
                try fm.removeItem(atPath: dst)
            }
            try fm.copyItem(atPath: src, toPath: dst)
            return true
        } catch {
            log("copy-failed \(src) → \(dst): \(error)")
            updateState { $0.lastError = "copy failed: \(src)" }
            return false
        }
    }

    /// Append bytes `[from ..< to]` from `src` to `dst`. Atomic-ish: if dst is
    /// smaller than expected (corrupted backup), falls back to full copy.
    private func performAppendDelta(src: String, dst: String, from: Int64, to: Int64) -> Bool {
        guard to > from else { return true }

        // Sanity: the backup file should be exactly `from` bytes.
        let backupSize = (try? fm.attributesOfItem(atPath: dst)[.size] as? Int64) ?? -1
        if backupSize != from {
            log("backup-size-drift \(dst) expected=\(from) actual=\(backupSize) — doing full copy")
            return performFullCopy(src: src, dst: dst)
        }

        guard let srcHandle = FileHandle(forReadingAtPath: src) else {
            log("open-src-failed \(src)")
            return performFullCopy(src: src, dst: dst)
        }
        defer { try? srcHandle.close() }

        guard let dstHandle = FileHandle(forWritingAtPath: dst) else {
            log("open-dst-failed \(dst)")
            return performFullCopy(src: src, dst: dst)
        }
        defer { try? dstHandle.close() }

        do {
            try srcHandle.seek(toOffset: UInt64(from))
            try dstHandle.seekToEnd()

            let chunkSize = 1 << 20   // 1 MiB chunks
            var remaining = to - from
            while remaining > 0 {
                let take = Int(min(Int64(chunkSize), remaining))
                let chunk = srcHandle.readData(ofLength: take)
                if chunk.isEmpty { break }
                try dstHandle.write(contentsOf: chunk)
                remaining -= Int64(chunk.count)
                if chunk.count < take { break }   // short read — source shrank under us
            }
            return true
        } catch {
            log("append-failed \(src) → \(dst): \(error)")
            // Try to recover with a full copy
            return performFullCopy(src: src, dst: dst)
        }
    }

    // MARK: - Paths

    private func computeBackupPath(forSource src: String) -> String {
        let suffix = String(src.dropFirst(BackupEngine.sourceRoot.count))   // "/proj/sess.jsonl"
        return BackupEngine.backupMirrorRoot.path + suffix
    }

    // MARK: - First-line signature

    /// Read up to the first newline of the source file and return it.
    /// Used as a sentinel to detect file rewrites that happen to leave the
    /// size growing (so a naive size-based check would treat them as a
    /// normal append). Capped at 1 KB so a malformed source without
    /// newlines doesn't pull the whole file into memory.
    private func readFirstLineSignature(srcPath: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: srcPath) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: 1024)) ?? Data()
        guard !chunk.isEmpty else { return nil }
        if let nlIndex = chunk.firstIndex(of: 0x0A) {
            let line = chunk[..<nlIndex]
            return String(decoding: line, as: UTF8.self)
        }
        // No newline within 1KB — use the entire chunk.
        return String(decoding: chunk, as: UTF8.self)
    }

    // MARK: - Utility

    private func stat(path: String) -> (exists: Bool, size: Int64, mtime: Double) {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
            return (false, 0, 0)
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (true, size, mtime)
    }

    private func ensureFreeSpace() -> Bool {
        let values = try? BackupEngine.backupHome.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = values?.volumeAvailableCapacityForImportantUsage {
            if free < freeSpaceFloorBytes {
                updateState { $0.lowDiskSpace = true }
                log("paused: low disk space free=\(free)")
                return false
            }
        }
        updateState { $0.lowDiskSpace = false }
        return true
    }

    private func updateState(_ block: @escaping (BackupEngine) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            block(self)
        }
    }

    private func refreshStatsAsync() {
        let s = manifest.stats()
        let when = Date()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.trackedFiles = s.trackedFiles
            self.livingSourceFiles = s.livingSourceFiles
            self.orphanedBackupFiles = s.orphanedBackupFiles
            self.totalBackupBytes = s.totalBackupBytes
            self.lastSyncAt = when
        }
    }

    private func refreshStatsSync() {
        let s = manifest.stats()
        self.trackedFiles = s.trackedFiles
        self.livingSourceFiles = s.livingSourceFiles
        self.orphanedBackupFiles = s.orphanedBackupFiles
        self.totalBackupBytes = s.totalBackupBytes
    }

    // MARK: - Logging

    private func log(_ message: String) {
        let line = "\(BackupEngine.timestampFormatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: BackupEngine.logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            _ = try? data.write(to: BackupEngine.logURL, options: [.atomic])
        }
    }

    /// Local copy of the fractional-second formatter so this module is
    /// self-contained (the app target has its own copy in SessionCreator).
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
