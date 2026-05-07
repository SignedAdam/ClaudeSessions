import Foundation
import SwiftUI

/// Soft visibility control for sessions and projects.
///
/// "Hide" is non-destructive: we just record the session/project IDs in a
/// JSON config at `~/.claude-sessions-app/hidden.json`. No files move.
/// Hidden items can be revealed again by toggling `showHidden`, after
/// which you right-click them to unhide.
///
/// Separate from ArchiveService, which physically moves files out of
/// Claude Code's directory. Hide is fast and reversible; archive is
/// filesystem-level.
@MainActor
final class HiddenStore: ObservableObject {
    static let shared = HiddenStore()

    @Published private(set) var hiddenSessionIds: Set<String> = []
    @Published private(set) var hiddenProjectIds: Set<String> = []

    /// Whether hidden items should still render in the sidebar (with muted
    /// styling). When false, they're completely invisible.
    @Published var showHidden: Bool {
        didSet { UserDefaults.standard.set(showHidden, forKey: "showHiddenItems") }
    }

    private let configPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = home + "/.claude-sessions-app/hidden.json"
        self.showHidden = UserDefaults.standard.bool(forKey: "showHiddenItems")
        load()
    }

    // MARK: - Queries

    func isSessionHidden(_ id: String) -> Bool { hiddenSessionIds.contains(id) }
    func isProjectHidden(_ id: String) -> Bool { hiddenProjectIds.contains(id) }

    // MARK: - Mutations

    func toggleSessionHidden(_ id: String) {
        if hiddenSessionIds.contains(id) {
            hiddenSessionIds.remove(id)
        } else {
            hiddenSessionIds.insert(id)
        }
        save()
    }

    func hideSession(_ id: String) {
        hiddenSessionIds.insert(id)
        save()
    }

    func unhideSession(_ id: String) {
        hiddenSessionIds.remove(id)
        save()
    }

    func toggleProjectHidden(_ id: String) {
        if hiddenProjectIds.contains(id) {
            hiddenProjectIds.remove(id)
        } else {
            hiddenProjectIds.insert(id)
        }
        save()
    }

    func hideProject(_ id: String) {
        hiddenProjectIds.insert(id)
        save()
    }

    func unhideProject(_ id: String) {
        hiddenProjectIds.remove(id)
        save()
    }

    /// Remove any stale IDs for sessions/projects that no longer exist.
    /// Call after ProjectScanner.scan() completes.
    func prune(validSessionIds: Set<String>, validProjectIds: Set<String>) {
        let prunedSessions = hiddenSessionIds.intersection(validSessionIds)
        let prunedProjects = hiddenProjectIds.intersection(validProjectIds)
        if prunedSessions.count != hiddenSessionIds.count || prunedProjects.count != hiddenProjectIds.count {
            hiddenSessionIds = prunedSessions
            hiddenProjectIds = prunedProjects
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let sessions = obj["hiddenSessions"] as? [String] {
            hiddenSessionIds = Set(sessions)
        }
        if let projects = obj["hiddenProjects"] as? [String] {
            hiddenProjectIds = Set(projects)
        }
    }

    private func save() {
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let obj: [String: Any] = [
            "hiddenSessions": Array(hiddenSessionIds).sorted(),
            "hiddenProjects": Array(hiddenProjectIds).sorted()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }
}
