import Foundation
import SwiftUI

/// Favorited/starred sessions. Non-destructive, config-only.
///
/// Starred sessions surface in a dedicated "Favorites" section at the top
/// of the sidebar, above all project folders. The underlying session still
/// lives in its project and can be toggled on/off freely.
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var favoriteSessionIds: Set<String> = []

    private let configPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = home + "/.claude-sessions-app/favorites.json"
        load()
    }

    // MARK: - Queries

    func isFavorite(_ id: String) -> Bool { favoriteSessionIds.contains(id) }

    var count: Int { favoriteSessionIds.count }

    // MARK: - Mutations

    func toggle(_ id: String) {
        if favoriteSessionIds.contains(id) {
            favoriteSessionIds.remove(id)
        } else {
            favoriteSessionIds.insert(id)
        }
        save()
    }

    func add(_ id: String) {
        favoriteSessionIds.insert(id)
        save()
    }

    func remove(_ id: String) {
        favoriteSessionIds.remove(id)
        save()
    }

    /// Remove any IDs that no longer correspond to real sessions.
    func prune(validSessionIds: Set<String>) {
        let pruned = favoriteSessionIds.intersection(validSessionIds)
        if pruned.count != favoriteSessionIds.count {
            favoriteSessionIds = pruned
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = obj["favoriteSessions"] as? [String] else {
            return
        }
        favoriteSessionIds = Set(ids)
    }

    private func save() {
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let obj: [String: Any] = [
            "favoriteSessions": Array(favoriteSessionIds).sorted()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }
}
