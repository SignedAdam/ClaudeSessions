import Foundation

/// Resolves a Claude Code project slug back to a real on-disk cwd.
///
/// Claude Code encodes project paths into directory names by replacing both
/// `/` and `.` with `-`. That's a lossy transform — `/foo/bar` and `/foo-bar`
/// both encode to `-foo-bar` — so a naive reversal is ambiguous.
///
/// Worse, some Claude Code versions historically wrote a wrong `cwd` and
/// `projectPath` into the JSONL and `sessions-index.json` themselves, so we
/// can't always trust those either.
///
/// Strategy: enumerate plausible reversals (each `-` is either `/` or `-`)
/// and return the first candidate that exists on disk.
enum SlugResolver {

    /// Given a slug like `-Users-alice-dev-claude-convo-viewer-ClaudeSessions`,
    /// return the real path on disk if exactly one candidate exists. Falls
    /// back to the all-slashes interpretation when nothing exists (caller
    /// can still try it; better than nothing).
    static func resolveCwd(forSlug slug: String) -> String? {
        let cleaned = slug.hasPrefix("-") ? String(slug.dropFirst()) : slug
        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return nil }

        let fm = FileManager.default
        var candidates: [String] = ["/" + parts[0]]

        for i in 1..<parts.count {
            let next = parts[i]
            var nextRound: [String] = []
            for c in candidates {
                // Slash extension only viable if the current prefix is a real directory
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: c, isDirectory: &isDir), isDir.boolValue {
                    nextRound.append(c + "/" + next)
                }
                // Dash extension always plausible (could be a literal hyphen or a `.`)
                nextRound.append(c + "-" + next)
            }
            // Deduplicate while preserving order
            var seen = Set<String>()
            candidates = nextRound.filter { seen.insert($0).inserted }
        }

        // Final filter: must exist as a directory
        let existing = candidates.filter { path in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }

        // Prefer the longest existing path (most slashes resolved correctly)
        return existing.sorted { $0.count > $1.count }.first
    }

    /// Convenience: resolve from the slug directory name (last path component
    /// of `~/.claude/projects/<slug>/`).
    static func resolveCwd(forProjectDir dir: String) -> String? {
        let slug = (dir as NSString).lastPathComponent
        return resolveCwd(forSlug: slug)
    }

    /// Best-effort cwd for a session. Tries (1) the slug-based resolution
    /// since that's grounded in filesystem reality, (2) the recorded value
    /// from the JSONL/index, and (3) the recorded value as-is even if it
    /// doesn't exist (so `claude --resume` can still report a useful error).
    static func bestCwd(slug: String?, recorded: String?) -> String? {
        if let slug = slug, let resolved = resolveCwd(forSlug: slug) {
            return resolved
        }
        if let recorded = recorded {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: recorded, isDirectory: &isDir),
               isDir.boolValue {
                return recorded
            }
            // Even if it doesn't exist, return it as a last resort
            return recorded
        }
        return nil
    }
}
