import Foundation

struct BackupService {
    private let backupRoot: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.backupRoot = home + "/.claude-sessions-backups"
    }

    /// Backup the original file before saving. Returns the backup path.
    func backup(filePath: String, sessionId: String) throws -> String {
        let fm = FileManager.default

        // Create backup directory
        let sessionDir = backupRoot + "/" + sessionId
        try fm.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)

        // Generate timestamped filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let backupPath = sessionDir + "/" + timestamp + ".jsonl"

        // Copy the original file
        try fm.copyItem(atPath: filePath, toPath: backupPath)

        // Enforce retention — keep last 20
        enforceRetention(sessionDir: sessionDir)

        return backupPath
    }

    private func enforceRetention(sessionDir: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionDir) else { return }

        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }.sorted()
        let maxBackups = 20

        if jsonlFiles.count > maxBackups {
            let toDelete = jsonlFiles.prefix(jsonlFiles.count - maxBackups)
            for file in toDelete {
                try? fm.removeItem(atPath: sessionDir + "/" + file)
            }
        }
    }
}
