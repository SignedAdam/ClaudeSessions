import Foundation

struct ProjectScanner {
    /// Scan the default `~/.claude/projects/` root only.
    /// Kept for callers that don't know about ScanRootStore.
    func scan() async -> [Project] {
        await scan(roots: [ScanRootStore.defaultRoot])
    }

    /// Scan one or more roots and return the union of their projects.
    /// Each project is tagged with its `sourceRoot` and gets a composite id
    /// (`<rootKey>:<slug>`) so SwiftUI ForEach diffing stays correct when
    /// multiple roots host a project with the same slug.
    func scan(roots: [URL]) async -> [Project] {
        var all: [Project] = []
        for root in roots {
            all.append(contentsOf: await scanOne(root: root))
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return all
    }

    private func scanOne(root: URL) async -> [Project] {
        let fm = FileManager.default
        let claudeProjectsPath = root.path
        guard let dirContents = try? fm.contentsOfDirectory(atPath: claudeProjectsPath) else {
            return []
        }

        let rootKey = ScanRootStore.rootKey(for: root)
        var projects: [Project] = []

        for dirName in dirContents {
            let dirPath = claudeProjectsPath + "/" + dirName
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
            // Skip hidden dirs
            guard !dirName.hasPrefix(".") else { continue }

            let (projectName, originalPath) = deriveProjectName(slug: dirName, dirPath: dirPath)

            var sessions: [SessionInfo] = []
            var indexedSessionIds: Set<String> = Set()

            // 1. Try reading sessions-index.json
            let indexPath = dirPath + "/sessions-index.json"
            if let indexData = fm.contents(atPath: indexPath),
               let index = try? JSONDecoder().decode(SessionsIndex.self, from: indexData) {
                for entry in index.entries {
                    guard entry.isSidechain != true else { continue }
                    let sessionId = entry.sessionId
                    indexedSessionIds.insert(sessionId)

                    let jsonlPath = entry.fullPath ?? (dirPath + "/" + sessionId + ".jsonl")
                    guard fm.fileExists(atPath: jsonlPath) else { continue }

                    let title = entry.summary ?? entry.firstPrompt?.prefix(60).description ?? "Untitled"
                    let created = entry.created.flatMap { DateFormatting.parseISO($0) } ?? Date.distantPast
                    let modified = entry.modified.flatMap { DateFormatting.parseISO($0) } ?? created

                    sessions.append(SessionInfo(
                        id: sessionId,
                        filePath: jsonlPath,
                        title: title,
                        firstPrompt: entry.firstPrompt,
                        messageCount: entry.messageCount ?? 0,
                        created: created,
                        modified: modified,
                        gitBranch: entry.gitBranch,
                        projectPath: entry.projectPath ?? originalPath,
                        isFromIndex: true
                    ))
                }
            }

            // 2. Discover non-indexed JSONL files
            if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
                for file in files {
                    guard file.hasSuffix(".jsonl") else { continue }
                    let sessionId = String(file.dropLast(6)) // remove .jsonl
                    guard !indexedSessionIds.contains(sessionId) else { continue }

                    let filePath = dirPath + "/" + file
                    let attrs = try? fm.attributesOfItem(atPath: filePath)
                    let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                    let creationDate = (attrs?[.creationDate] as? Date) ?? modDate

                    // Extract first user message
                    let firstPrompt = extractFirstPrompt(filePath: filePath)
                    let title = firstPrompt?.prefix(60).description ?? "Untitled"

                    sessions.append(SessionInfo(
                        id: sessionId,
                        filePath: filePath,
                        title: title,
                        firstPrompt: firstPrompt,
                        messageCount: 0, // unknown without parsing
                        created: creationDate,
                        modified: modDate,
                        gitBranch: nil,
                        projectPath: originalPath,
                        isFromIndex: false
                    ))
                }
            }

            // 3. Discover subagent sessions for each parent session.
            //    Format: <projectDir>/<sessionId>/subagents/agent-*.jsonl
            for i in sessions.indices {
                let parentId = sessions[i].id
                let subagentDir = dirPath + "/" + parentId + "/subagents"
                guard fm.fileExists(atPath: subagentDir) else { continue }
                guard let files = try? fm.contentsOfDirectory(atPath: subagentDir) else { continue }

                var subs: [SessionInfo] = []
                for file in files where file.hasSuffix(".jsonl") {
                    let agentId = String(file.dropLast(6))
                    let agentPath = subagentDir + "/" + file
                    let attrs = try? fm.attributesOfItem(atPath: agentPath)
                    let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                    let creationDate = (attrs?[.creationDate] as? Date) ?? modDate

                    let firstPrompt = extractFirstPrompt(filePath: agentPath)
                    let title = firstPrompt.map { String($0.prefix(60)) } ?? "Subagent"

                    subs.append(SessionInfo(
                        id: agentId,
                        filePath: agentPath,
                        title: title,
                        firstPrompt: firstPrompt,
                        messageCount: 0,
                        created: creationDate,
                        modified: modDate,
                        gitBranch: nil,
                        projectPath: originalPath,
                        isFromIndex: false,
                        subagents: [],
                        isSubagent: true
                    ))
                }
                subs.sort { $0.created < $1.created }  // chronological order under parent
                sessions[i].subagents = subs
            }

            // Sort sessions by modified date, newest first
            sessions.sort { $0.modified > $1.modified }

            if !sessions.isEmpty {
                projects.append(Project(
                    id: rootKey + ":" + dirName,
                    slug: dirName,
                    sourceRoot: root,
                    name: projectName,
                    originalPath: originalPath,
                    sessions: sessions
                ))
            }
        }

        return projects
    }

    // MARK: - Project Name Derivation

    private func deriveProjectName(slug: String, dirPath: String) -> (name: String, originalPath: String) {
        // Try to get originalPath from sessions-index.json
        let indexPath = dirPath + "/sessions-index.json"
        if let data = FileManager.default.contents(atPath: indexPath),
           let index = try? JSONDecoder().decode(SessionsIndex.self, from: data),
           let origPath = index.originalPath {
            let name = projectNameFromPath(origPath)
            return (name, origPath)
        }

        // Fallback: parse from slug
        // Slug format: -Users-alice-dev-shortimize-backend
        let path = "/" + slug.dropFirst().replacingOccurrences(of: "-", with: "/")
        let name = projectNameFromPath(path)
        return (name, path)
    }

    private func projectNameFromPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~ (home)"
        }
        let lastComponent = (path as NSString).lastPathComponent
        return lastComponent.isEmpty ? "root" : lastComponent
    }

    // MARK: - Extract First Prompt

    private func extractFirstPrompt(filePath: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { handle.closeFile() }

        // Read first ~50KB to find first user message
        let chunk = handle.readData(ofLength: 50_000)
        let text = String(decoding: chunk, as: UTF8.self)
        let lines = text.components(separatedBy: "\n").prefix(50)
        let decoder = JSONDecoder()

        for line in lines {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let entry = try? decoder.decode(RawEntry.self, from: data) else { continue }
            if entry.type == .user, let msg = entry.message, case .text(let text) = msg.content {
                if entry.isCompactSummary != true {
                    return String(text.prefix(200))
                }
            }
        }
        return nil
    }
}
