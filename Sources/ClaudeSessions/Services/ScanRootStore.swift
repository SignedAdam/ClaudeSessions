import Foundation
import SwiftUI

/// Extra filesystem locations to scan in addition to the implicit default
/// (`~/.claude/projects/`). Useful for archived sets, mounted backups, or a
/// synced second machine's transcripts.
///
/// The default root is *implicit* — it's always returned by ``allRoots()``
/// and cannot be added or removed. The store only persists *custom* roots.
@MainActor
final class ScanRootStore: ObservableObject {
    static let shared = ScanRootStore()

    @Published private(set) var customRoots: [URL] = []

    private let configPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = home + "/.claude-sessions-app/scan-roots.json"
        load()
    }

    // MARK: - Queries

    /// The default root is always first; any custom roots follow in
    /// insertion order. Callers iterate this to drive scans.
    func allRoots() -> [URL] {
        [Self.defaultRoot] + customRoots
    }

    /// Stable canonical key for a root URL — used as the `rootHash` prefix
    /// in `Project.id` so SwiftUI ForEach diffing stays correct across
    /// roots that happen to host the same slug.
    static func rootKey(for url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        return String(UInt(bitPattern: resolved.hashValue), radix: 36)
    }

    static let defaultRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: home + "/.claude/projects", isDirectory: true)
    }()

    // MARK: - Mutations

    /// Add a custom root. Returns nil on success, or a human-readable
    /// reason for rejection (not a directory, unreadable, duplicate, or
    /// the default root).
    @discardableResult
    func addRoot(_ url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL

        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
            return "Path is not a directory."
        }
        guard fm.isReadableFile(atPath: resolved.path) else {
            return "Directory is not readable."
        }
        if Self.rootKey(for: resolved) == Self.rootKey(for: Self.defaultRoot) {
            return "The default ~/.claude/projects/ root is always included."
        }
        let resolvedKey = Self.rootKey(for: resolved)
        if customRoots.contains(where: { Self.rootKey(for: $0) == resolvedKey }) {
            return "That location is already in the list."
        }

        customRoots.append(resolved)
        save()
        return nil
    }

    func removeRoot(_ url: URL) {
        let key = Self.rootKey(for: url)
        let before = customRoots.count
        customRoots.removeAll { Self.rootKey(for: $0) == key }
        if customRoots.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = obj["customRoots"] as? [String] else {
            return
        }
        customRoots = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func save() {
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let obj: [String: Any] = [
            "customRoots": customRoots.map { $0.path }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }
}
