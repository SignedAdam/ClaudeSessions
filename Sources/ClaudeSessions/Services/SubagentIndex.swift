import Foundation

/// One row in the cross-project subagent browser. Pure-derivation from
/// the existing `[Project]` scan output — no new I/O.
struct SubagentIndexEntry: Identifiable {
    /// Composite id so SwiftUI ForEach stays stable across same-named
    /// agents that happen to share a UUID-ish suffix in different
    /// projects (vanishingly rare, but cheap to be correct).
    let id: String
    let subagent: SessionInfo
    let parent: SessionInfo
    let project: Project
    /// Best-effort agent name extracted from the JSONL filename when it
    /// matches `agent-<NAME>-<uuid>.jsonl`. Nil if the filename doesn't
    /// follow that convention.
    let agentName: String?
}

enum SubagentIndex {
    /// Flatten every project's subagents into a chronological-desc list.
    /// O(total subagent count); no allocations beyond the result array.
    static func build(from projects: [Project]) -> [SubagentIndexEntry] {
        var entries: [SubagentIndexEntry] = []
        for project in projects {
            for parent in project.sessions {
                for sub in parent.subagents {
                    entries.append(SubagentIndexEntry(
                        id: "\(project.id)::\(parent.id)::\(sub.id)",
                        subagent: sub,
                        parent: parent,
                        project: project,
                        agentName: extractAgentName(fromFile: sub.filePath)
                    ))
                }
            }
        }
        entries.sort { $0.subagent.modified > $1.subagent.modified }
        return entries
    }

    /// `agent-<NAME>-<uuid>.jsonl` → `<NAME>`. The trailing UUID has 5
    /// dash-separated parts (8-4-4-4-12); we strip the `agent-` prefix
    /// and those 5 trailing parts to recover the name. Returns nil when
    /// the filename doesn't conform.
    static func extractAgentName(fromFile path: String) -> String? {
        let base = (path as NSString).lastPathComponent
        guard base.hasSuffix(".jsonl") else { return nil }
        let stem = String(base.dropLast(6))      // strip ".jsonl"
        guard stem.hasPrefix("agent-") else { return nil }
        let withoutPrefix = String(stem.dropFirst("agent-".count))
        let parts = withoutPrefix.split(separator: "-", omittingEmptySubsequences: false)
        // Need at least one name part + 5 UUID parts
        guard parts.count >= 6 else { return nil }
        let nameParts = parts.dropLast(5)
        let name = nameParts.joined(separator: "-")
        return name.isEmpty ? nil : name
    }
}
