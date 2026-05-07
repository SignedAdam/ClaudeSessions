import Foundation

/// Computes a per-uuid set-diff between two JSONL versions.
///
/// Why per-uuid (not line-level): the JSONL is append-only with stable
/// uuids. The only changes between two versions are entries added or
/// removed. A line-level Myers diff would do extra work and produce
/// noisier output. The set-diff matches the file's semantics directly.
enum VersionDiffService {

    enum Side { case left, right }

    /// One diff hunk — an entry that exists in only one of the two files.
    struct Hunk: Identifiable, Hashable {
        let id: String        // uuid
        let side: Side        // .left = only in A (removed), .right = only in B (added)
        let entryType: String // "user" / "assistant" / "system" / "summary" / etc.
        let role: String      // "user" / "assistant" / "" — for the badge
        let preview: String   // first ~80 chars of message text or summary

        static func == (lhs: Hunk, rhs: Hunk) -> Bool { lhs.id == rhs.id && lhs.side == rhs.side }
        func hash(into h: inout Hasher) { h.combine(id); h.combine(side == .left) }
    }

    struct Result {
        let leftPath: String
        let rightPath: String
        let leftCount: Int
        let rightCount: Int
        let commonCount: Int
        let removed: [Hunk]   // in left, missing from right
        let added: [Hunk]     // in right, missing from left
    }

    /// Compute the diff. Filesystem-only — reads both files, parses each
    /// line as JSON, joins on `uuid`. Lines without a uuid (e.g. summary,
    /// custom-title, attachment events) are skipped because they can't be
    /// reliably matched across versions; that's an acceptable trade-off
    /// because they're not really "messages" — the user-visible content
    /// is the user/assistant entries which always have uuids.
    static func diff(left: String, right: String) -> Result {
        let leftEntries = readEntries(path: left)
        let rightEntries = readEntries(path: right)

        let leftIDs = Set(leftEntries.keys)
        let rightIDs = Set(rightEntries.keys)
        let removedIDs = leftIDs.subtracting(rightIDs)
        let addedIDs = rightIDs.subtracting(leftIDs)
        let common = leftIDs.intersection(rightIDs).count

        let removed = removedIDs.compactMap { id -> Hunk? in
            guard let dict = leftEntries[id] else { return nil }
            return makeHunk(id: id, side: .left, dict: dict)
        }.sorted { $0.preview < $1.preview }  // stable order

        let added = addedIDs.compactMap { id -> Hunk? in
            guard let dict = rightEntries[id] else { return nil }
            return makeHunk(id: id, side: .right, dict: dict)
        }.sorted { $0.preview < $1.preview }

        return Result(
            leftPath: left,
            rightPath: right,
            leftCount: leftEntries.count,
            rightCount: rightEntries.count,
            commonCount: common,
            removed: removed,
            added: added
        )
    }

    // MARK: - File reading

    private static func readEntries(path: String) -> [String: [String: Any]] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        var map: [String: [String: Any]] = [:]
        // Hand-split on newlines. JSONL is one object per line; we don't
        // need a streaming parser at the file sizes we cap at (25MB).
        let bytes = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        for slice in bytes {
            let lineData = Data(slice)
            guard let dict = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard let uuid = dict["uuid"] as? String else { continue }
            map[uuid] = dict
        }
        return map
    }

    private static func makeHunk(id: String, side: Side, dict: [String: Any]) -> Hunk {
        let entryType = (dict["type"] as? String) ?? "?"
        var role = ""
        if let msg = dict["message"] as? [String: Any] {
            role = (msg["role"] as? String) ?? ""
        }

        // Build a one-line preview from whichever shape this entry has.
        var preview = ""
        if let msg = dict["message"] as? [String: Any] {
            if let text = msg["content"] as? String {
                preview = text
            } else if let blocks = msg["content"] as? [[String: Any]] {
                // Take the first text block, or the first tool-use name.
                for block in blocks {
                    if let t = block["type"] as? String {
                        if t == "text", let s = block["text"] as? String {
                            preview = s
                            break
                        } else if t == "tool_use", let name = block["name"] as? String {
                            preview = "[tool] \(name)"
                            break
                        } else if t == "tool_result" {
                            if let s = block["content"] as? String {
                                preview = "[tool result] \(s)"
                            } else {
                                preview = "[tool result]"
                            }
                            break
                        }
                    }
                }
            }
        }
        if preview.isEmpty, let summary = dict["summary"] as? String {
            preview = summary
        }
        // Single-line, capped.
        let oneLine = preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let capped = oneLine.count > 100 ? String(oneLine.prefix(100)) + "…" : oneLine

        return Hunk(id: id, side: side, entryType: entryType, role: role, preview: capped)
    }
}
