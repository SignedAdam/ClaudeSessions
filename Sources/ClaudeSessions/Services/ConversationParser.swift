import Foundation

struct ConversationParser {
    private let decoder = JSONDecoder()

    func parse(data: Data, sessionId: String, filePath: String) -> Conversation {
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        var rawEntries: [IndexedEntry] = []
        var malformedCount = 0

        for (index, lineData) in lines.enumerated() {
            let rawString = String(decoding: lineData, as: UTF8.self)
            do {
                var entry = try decoder.decode(RawEntry.self, from: lineData)
                entry.rawJSON = rawString
                rawEntries.append(IndexedEntry(index: index, rawJSON: rawString, entry: entry))
            } catch {
                // Preserve malformed lines for round-tripping
                var fallback = RawEntry.unknown
                fallback.rawJSON = rawString
                rawEntries.append(IndexedEntry(index: index, rawJSON: rawString, entry: fallback))
                malformedCount += 1
            }
        }

        // Claude Code lets you press Esc and re-edit a prior user message
        // mid-conversation. The JSONL is append-only, so the abandoned
        // branch stays in the file — its entries become orphans whose
        // parentUuid chain no longer reaches the session tip. Compute the
        // set of uuids on the live branch (tip → root via parentUuid) so
        // display + stats ignore the discarded fork.
        // Detect whether this is a subagent JSONL. In a subagent file every
        // dialogue entry is marked `isSidechain: true` because the file's
        // contents *are* a sidechain — the spawned agent's turns. When we
        // open such a file directly we must NOT filter sidechains, otherwise
        // the whole conversation disappears.
        let isSubagentFile = looksLikeSubagentFile(filePath: filePath, entries: rawEntries)

        let activeBranch = buildActiveBranchSet(from: rawEntries)
        let displayMessages = buildDisplayMessages(
            from: rawEntries,
            activeBranch: activeBranch,
            includeSidechain: isSubagentFile
        )
        let stats = computeStats(
            from: rawEntries,
            activeBranch: activeBranch,
            includeSidechain: isSubagentFile
        )

        return Conversation(
            sessionId: sessionId,
            filePath: filePath,
            displayMessages: displayMessages,
            rawEntries: rawEntries,
            stats: stats
        )
    }

    // MARK: - Active branch detection

    /// Walks from the file's tip backward through parentUuid to identify
    /// the set of entries on the live conversation branch. Entries whose
    /// uuid is absent from this set were discarded when the user edited
    /// an earlier message in Claude Code (Esc + edit). If there's no
    /// obvious tip, we return a full set (signaled by nil) meaning
    /// "don't filter".
    private func buildActiveBranchSet(from entries: [IndexedEntry]) -> Set<String>? {
        // Map uuid → parentUuid for fast chain-walking
        var parentByUuid: [String: String?] = [:]
        for indexed in entries {
            if let u = indexed.entry.uuid {
                parentByUuid[u] = indexed.entry.parentUuid
            }
        }
        guard !parentByUuid.isEmpty else { return nil }

        // Tip = last user/assistant/system entry with a uuid that's part of
        // the main conversation. We must exclude sidechain entries (subagent
        // turns) — anchoring the walk on a sidechain entry would miss the
        // main conversation's branch entirely. File-history-snapshot,
        // progress, custom-title, etc. aren't dialogue and don't anchor.
        var tip: String?
        for indexed in entries.reversed() {
            let t = indexed.entry.type
            guard t == .user || t == .assistant || t == .system else { continue }
            guard indexed.entry.isSidechain != true else { continue }
            if let u = indexed.entry.uuid {
                tip = u
                break
            }
        }
        guard let startUuid = tip else { return nil }

        var active: Set<String> = []
        var cur: String? = startUuid
        var guardCount = 0
        while let u = cur, parentByUuid[u] != nil, guardCount < 200_000 {
            if !active.insert(u).inserted { break }  // cycle guard
            cur = parentByUuid[u] ?? nil
            guardCount += 1
        }

        // If the walk reached every uuid, there's no fork — skip filtering
        // entirely so we don't risk excluding anything from a clean session.
        if active.count == parentByUuid.count { return nil }
        return active
    }

    // MARK: - Build Display Messages

    /// Heuristic: a file is a subagent file if (a) it lives in a `subagents/`
    /// directory under a project — that's how Claude Code stores them — or
    /// (b) every dialogue entry is `isSidechain == true`. The path check is
    /// cheap and authoritative; the entry-content check is a fallback for
    /// non-standard locations.
    private func looksLikeSubagentFile(filePath: String, entries: [IndexedEntry]) -> Bool {
        if filePath.contains("/subagents/") { return true }
        var hasDialogue = false
        for indexed in entries {
            switch indexed.entry.type {
            case .user, .assistant:
                hasDialogue = true
                if indexed.entry.isSidechain != true { return false }
            default:
                continue
            }
        }
        return hasDialogue   // all dialogue is sidechain → subagent
    }

    private func buildDisplayMessages(
        from entries: [IndexedEntry],
        activeBranch: Set<String>?,
        includeSidechain: Bool = false
    ) -> [DisplayMessage] {
        var messages: [DisplayMessage] = []
        var pendingToolCalls: [String: ToolCallMessage] = [:]  // keyed by tool_use block id
        var pendingToolCallOrder: [String] = []

        for indexed in entries {
            let entry = indexed.entry
            let timestamp = entry.timestamp.flatMap { DateFormatting.parseISO($0) }
            let entryIndex = indexed.index

            // Drop entries from abandoned branches (user pressed Esc in
            // Claude Code and re-edited an earlier message).
            if let active = activeBranch, let u = entry.uuid, !active.contains(u) {
                continue
            }

            switch entry.type {
            case .user:
                guard let msg = entry.message else { continue }
                // Skip sidechain messages
                if entry.isSidechain == true && !includeSidechain { continue }

                switch msg.content {
                case .text(let text):
                    // User text message
                    if entry.isCompactSummary == true {
                        // Still show as user text but flagged
                    }
                    messages.append(.userText(UserTextMessage(
                        id: entry.uuid ?? UUID().uuidString,
                        text: text,
                        timestamp: timestamp,
                        timestampRaw: entry.timestamp,
                        isCompactSummary: entry.isCompactSummary ?? false,
                        entryIndex: entryIndex
                    )))

                case .blocks(let blocks):
                    // Tool result message(s)
                    for block in blocks {
                        if case .toolResult(let result) = block {
                            let resultText = result.content.displayText
                            let toolResultMsg = ToolResultMessage(
                                id: result.toolUseId,
                                toolUseId: result.toolUseId,
                                resultText: resultText,
                                isError: result.isError ?? false,
                                timestamp: timestamp,
                                entryIndex: entryIndex
                            )

                            // Try to pair with pending tool call
                            if let call = pendingToolCalls.removeValue(forKey: result.toolUseId) {
                                pendingToolCallOrder.removeAll { $0 == result.toolUseId }
                                messages.append(.toolInteraction(ToolInteraction(
                                    id: call.id,
                                    toolCall: call,
                                    toolResult: toolResultMsg
                                )))
                            } else {
                                messages.append(.toolResult(toolResultMsg))
                            }
                        }
                    }
                }

            case .assistant:
                guard let msg = entry.message else { continue }
                if entry.isSidechain == true && !includeSidechain { continue }

                switch msg.content {
                case .text:
                    break // Assistant messages always use blocks
                case .blocks(let blocks):
                    for (blockIdx, block) in blocks.enumerated() {
                        switch block {
                        case .text(let textBlock):
                            let text = textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if text.isEmpty { continue }
                            messages.append(.assistantText(AssistantTextMessage(
                                id: (entry.uuid ?? UUID().uuidString) + "-\(blockIdx)",
                                text: textBlock.text,
                                timestamp: timestamp,
                                timestampRaw: entry.timestamp,
                                model: msg.model,
                                isApiError: entry.isApiErrorMessage ?? false,
                                tokenUsage: msg.usage,
                                entryIndex: entryIndex,
                                blockIndex: blockIdx
                            )))
                        case .toolUse(let toolBlock):
                            // Flush any unpaired tool calls before this one
                            // (they'll be standalone)
                            let inputDict = toolBlock.input.dictValue ?? [:]
                            let summary = toolCallSummary(name: toolBlock.name, input: inputDict)
                            let desc = inputDict["description"] as? String
                            let callMsg = ToolCallMessage(
                                id: toolBlock.id,
                                toolName: toolBlock.name,
                                input: inputDict,
                                description: desc,
                                summary: summary,
                                timestamp: timestamp,
                                entryIndex: entryIndex
                            )
                            pendingToolCalls[toolBlock.id] = callMsg
                            pendingToolCallOrder.append(toolBlock.id)
                        default:
                            break
                        }
                    }
                }

            case .system:
                if entry.isSidechain == true && !includeSidechain { continue }

                if entry.subtype == "compact_boundary" {
                    messages.append(.compactBoundary(CompactBoundaryMessage(
                        id: entry.uuid ?? UUID().uuidString,
                        timestamp: timestamp,
                        preTokens: entry.compactMetadata?.preTokens,
                        trigger: entry.compactMetadata?.trigger,
                        entryIndex: entryIndex
                    )))
                } else if let subtype = entry.subtype {
                    let contentStr: String
                    if let c = entry.content?.stringValue {
                        contentStr = c
                    } else if subtype == "turn_duration", let ms = entry.durationMs {
                        let count = entry.messageCount ?? 0
                        contentStr = "Turn took \(String(format: "%.1f", Double(ms) / 1000))s, \(count) messages"
                    } else {
                        contentStr = subtype
                    }

                    messages.append(.systemMessage(SystemDisplayMessage(
                        id: entry.uuid ?? UUID().uuidString,
                        subtype: subtype,
                        content: contentStr,
                        timestamp: timestamp,
                        durationMs: entry.durationMs,
                        entryIndex: entryIndex
                    )))
                }

            default:
                // Non-message types (file-history-snapshot, progress, etc.) — skip for display
                break
            }
        }

        // Flush remaining unpaired tool calls
        for id in pendingToolCallOrder {
            if let call = pendingToolCalls.removeValue(forKey: id) {
                messages.append(.toolCall(call))
            }
        }

        return messages
    }

    // MARK: - Tool Call Summary

    private func toolCallSummary(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            return (input["command"] as? String) ?? ""
        case "Read", "Write", "Edit":
            return (input["file_path"] as? String) ?? ""
        case "Grep", "Glob":
            return (input["pattern"] as? String) ?? ""
        case "Agent":
            return (input["description"] as? String) ?? (input["prompt"] as? String)?.prefix(80).description ?? ""
        case "TaskCreate", "TaskUpdate":
            return (input["subject"] as? String) ?? (input["id"] as? String) ?? ""
        case "WebSearch":
            return (input["query"] as? String) ?? ""
        default:
            return name
        }
    }

    // MARK: - Stats

    private func computeStats(
        from entries: [IndexedEntry],
        activeBranch: Set<String>?,
        includeSidechain: Bool = false
    ) -> ConversationStats {
        var userCount = 0
        var assistantCount = 0
        var toolCount = 0
        var systemCount = 0
        var firstTs: Date?
        var lastTs: Date?

        for indexed in entries {
            let entry = indexed.entry
            if entry.isSidechain == true && !includeSidechain { continue }
            if let active = activeBranch, let u = entry.uuid, !active.contains(u) { continue }

            let ts = entry.timestamp.flatMap { DateFormatting.parseISO($0) }
            if let ts = ts {
                if firstTs == nil || ts < firstTs! { firstTs = ts }
                if lastTs == nil || ts > lastTs! { lastTs = ts }
            }

            switch entry.type {
            case .user:
                if let msg = entry.message {
                    switch msg.content {
                    case .text:
                        if entry.isCompactSummary != true {
                            userCount += 1
                        }
                    case .blocks:
                        break // tool results don't count as user messages
                    }
                }
            case .assistant:
                if entry.isApiErrorMessage != true {
                    if let msg = entry.message, case .blocks(let blocks) = msg.content {
                        let hasText = blocks.contains { if case .text = $0 { return true } else { return false } }
                        if hasText { assistantCount += 1 }
                        toolCount += blocks.filter { if case .toolUse = $0 { return true } else { return false } }.count
                    }
                }
            case .system:
                systemCount += 1
            default:
                break
            }
        }

        return ConversationStats(
            userMessageCount: userCount,
            assistantMessageCount: assistantCount,
            toolCallCount: toolCount,
            systemMessageCount: systemCount,
            firstTimestamp: firstTs,
            lastTimestamp: lastTs
        )
    }
}

// MARK: - RawEntry convenience

extension RawEntry {
    /// A fallback entry for malformed lines
    static var unknown: RawEntry {
        RawEntry(
            type: .unknown, uuid: nil, parentUuid: nil, timestamp: nil, sessionId: nil,
            isSidechain: nil, userType: nil, entrypoint: nil, cwd: nil, version: nil,
            gitBranch: nil, slug: nil, message: nil, promptId: nil, permissionMode: nil,
            isCompactSummary: nil, isVisibleInTranscriptOnly: nil, isMeta: nil,
            sourceToolAssistantUUID: nil, toolUseResult: nil, requestId: nil,
            isApiErrorMessage: nil, subtype: nil, durationMs: nil, messageCount: nil,
            content: nil, level: nil, logicalParentUuid: nil, compactMetadata: nil,
            url: nil, upgradeNudge: nil, customTitle: nil, lastPrompt: nil,
            agentName: nil, operation: nil, snapshot: nil, isSnapshotUpdate: nil,
            messageId: nil, attachment: nil, data: nil, toolUseID: nil,
            parentToolUseID: nil, rawJSON: nil
        )
    }
}
