import Foundation

/// Per-conversation token + cost analytics.
///
/// Derived from the `usage` blocks attached to every assistant message in the
/// JSONL. Precise for raw API-reported numbers (input/output/cache tokens,
/// therefore dollar cost). Approximate for the category breakdown
/// (messages vs tools vs system) since the JSONL doesn't record Claude
/// Code's loaded system prompt / tool defs / memory separately — we
/// estimate those as "overhead" by subtraction.
struct ContextMetrics {

    // MARK: - Model sizing & pricing

    /// Context-window size in tokens per model family.
    ///
    /// - Opus models (all current generations): 1M tokens by default
    /// - Sonnet / Haiku: 200k, unless tagged with `[1m]` (paid 1M-context tier)
    /// - Unknown model: conservative 200k
    static func contextWindow(for model: String?) -> Int {
        guard let m = model?.lowercased() else { return 200_000 }
        if m.contains("[1m]") { return 1_000_000 }
        if m.contains("opus") { return 1_000_000 }
        return 200_000
    }

    /// USD per million tokens.
    struct Pricing {
        let inputPerM: Double
        let outputPerM: Double
        let cacheReadDiscount: Double  // e.g. 0.10 = 90% off input
        let cacheWritePremium: Double  // e.g. 1.25 = 25% extra over input
    }

    static func pricing(for model: String?) -> Pricing {
        let m = (model ?? "").lowercased()
        if m.contains("opus") {
            return Pricing(inputPerM: 15.0, outputPerM: 75.0,
                           cacheReadDiscount: 0.10, cacheWritePremium: 1.25)
        }
        if m.contains("sonnet") {
            return Pricing(inputPerM: 3.0, outputPerM: 15.0,
                           cacheReadDiscount: 0.10, cacheWritePremium: 1.25)
        }
        if m.contains("haiku") {
            return Pricing(inputPerM: 1.0, outputPerM: 5.0,
                           cacheReadDiscount: 0.10, cacheWritePremium: 1.25)
        }
        // Unknown — conservative mid-tier estimate
        return Pricing(inputPerM: 3.0, outputPerM: 15.0,
                       cacheReadDiscount: 0.10, cacheWritePremium: 1.25)
    }

    // MARK: - Result

    struct Result {
        /// Peak context ever sent to the model in this session
        /// (input + cache_read + cache_creation at the heaviest turn).
        let peakContextTokens: Int

        /// The model this session ran on (may be mixed across turns — we use
        /// whichever the last assistant message reported).
        let model: String?

        /// Context window for that model.
        let contextWindowTokens: Int

        /// Fill ratio — peakContextTokens / contextWindowTokens (0–1+).
        var fillRatio: Double {
            guard contextWindowTokens > 0 else { return 0 }
            return Double(peakContextTokens) / Double(contextWindowTokens)
        }

        /// Cumulative tokens (across all assistant messages).
        let totalInputTokens: Int
        let totalOutputTokens: Int
        let totalCacheReadTokens: Int
        let totalCacheCreationTokens: Int

        /// Cache-hit rate: cache_read / (cache_read + real input + cache_creation).
        /// Higher is better (more tokens served from cache = cheaper + faster).
        var cacheHitRate: Double {
            let denom = Double(totalCacheReadTokens + totalInputTokens + totalCacheCreationTokens)
            return denom > 0 ? Double(totalCacheReadTokens) / denom : 0
        }

        /// Estimated USD cost for the whole session.
        let estimatedCostUSD: Double

        /// Dialogue-only token estimate — what you'd get if you extracted
        /// the human+claude text and sent it as a fresh prompt. Approximated
        /// via character count / 4 (the industry rule of thumb).
        let dialogueTokenEstimate: Int

        /// Approximate category breakdown of the peak context.
        /// These are estimates based on the text content; they won't match
        /// Claude Code's /context exactly because we don't see the loaded
        /// system prompt / tool defs / memory files. Those are rolled into
        /// "overhead" as the residual.
        struct Breakdown {
            let userMessages: Int       // approx tokens
            let assistantMessages: Int  // approx tokens
            let toolCalls: Int          // approx tokens
            let toolResults: Int        // approx tokens
            let system: Int             // approx tokens
            let overhead: Int           // residual (system prompt + tools + memory + skills)
            let free: Int               // contextWindow - peak
        }
        let breakdown: Breakdown
    }

    // MARK: - Computation

    func compute(for conversation: Conversation) -> Result {
        var peak = 0
        var lastModel: String? = nil
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreation = 0
        var runningCost: Double = 0

        // Walk assistant entries, summing and tracking peak
        for indexed in conversation.rawEntries {
            guard indexed.entry.type == .assistant,
                  let msg = indexed.entry.message,
                  let usage = msg.usage else { continue }

            let input = usage.inputTokens ?? 0
            let output = usage.outputTokens ?? 0
            let cacheRead = usage.cacheReadInputTokens ?? 0
            let cacheCreation = usage.cacheCreationInputTokens ?? 0

            let turnContext = input + cacheRead + cacheCreation
            if turnContext > peak { peak = turnContext }

            totalInput += input
            totalOutput += output
            totalCacheRead += cacheRead
            totalCacheCreation += cacheCreation
            lastModel = msg.model

            let price = ContextMetrics.pricing(for: msg.model)
            runningCost += cost(for: input, output: output,
                                cacheRead: cacheRead, cacheCreation: cacheCreation,
                                pricing: price)
        }

        let model = lastModel
        let window = ContextMetrics.contextWindow(for: model)

        // Dialogue-only approximation — content-aware estimator across
        // user + assistant text blocks (prose vs. code vs. symbol-heavy).
        let rawDialogueTokens = estimateDialogueTokens(conversation)

        // Cleaning can only REMOVE content (tool calls, results, system
        // messages, overhead), never add it. So the cleaned estimate must
        // never exceed the real peak. If our approximation overshoots,
        // clamp it — otherwise the "clean" pill misleadingly suggests
        // cleaning would grow the context.
        let dialogueTokens = peak > 0 ? min(rawDialogueTokens, peak) : rawDialogueTokens

        // A cleaned or brand-new session has no `usage` data on its
        // assistant messages, so `peak` stays at 0. That's misleading —
        // the session has content, just no API-reported token counts.
        // Fall back to the dialogue estimate in that case so the badge
        // reflects actual size rather than zero.
        let effectivePeak = peak > 0 ? peak : dialogueTokens

        // Category approximation — character counts per category, /4.
        let breakdown = computeBreakdown(
            conversation: conversation,
            peak: effectivePeak,
            window: window
        )

        return Result(
            peakContextTokens: effectivePeak,
            model: model,
            contextWindowTokens: window,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheCreationTokens: totalCacheCreation,
            estimatedCostUSD: runningCost,
            dialogueTokenEstimate: dialogueTokens,
            breakdown: breakdown
        )
    }

    // MARK: - Helpers

    private func cost(for input: Int, output: Int,
                      cacheRead: Int, cacheCreation: Int,
                      pricing: Pricing) -> Double {
        let inputCost  = Double(input) * pricing.inputPerM / 1_000_000
        let outputCost = Double(output) * pricing.outputPerM / 1_000_000
        let cacheReadCost = Double(cacheRead) * pricing.inputPerM * pricing.cacheReadDiscount / 1_000_000
        let cacheWriteCost = Double(cacheCreation) * pricing.inputPerM * pricing.cacheWritePremium / 1_000_000
        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }

    /// Content-aware token estimate.
    ///
    /// Universal `chars / 4` is a ~15% overestimate for pure prose and a
    /// ~20% underestimate for code. Claude's BPE tokenizer (like other
    /// modern tokenizers) packs common English words efficiently and splits
    /// code / symbol-heavy text more finely.
    ///
    /// We split the text by code fences and score each region separately:
    ///   - Code regions: ~3.3 chars/token
    ///   - High-symbol prose: ~3.8 chars/token
    ///   - Regular prose: ~4.5 chars/token
    ///
    /// Not exact — a real tokenizer would be — but closer to truth than
    /// a single divisor, especially for the mix of code + prose typical
    /// in Claude Code conversations.
    static func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        // Split into code-fenced vs. non-fenced regions
        var proseChars = 0
        var codeChars = 0
        var inCode = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                continue
            }
            let len = line.count + 1   // +1 for the newline we split on
            if inCode { codeChars += len } else { proseChars += len }
        }

        // Detect code-density even outside fences (inline code, symbols).
        let specials: Set<Character> = ["{", "}", "[", "]", "(", ")", "<", ">", "=", "|", ";", "&", "@", "#", "$", "/", "\\"]
        let specialCount = text.reduce(0) { $0 + (specials.contains($1) ? 1 : 0) }
        let specialRatio = Double(specialCount) / Double(max(text.count, 1))

        let proseDivisor: Double = specialRatio > 0.05 ? 3.8 : 4.5
        let codeDivisor: Double = 3.3

        let proseTokens = Double(proseChars) / proseDivisor
        let codeTokens  = Double(codeChars) / codeDivisor
        return Int((proseTokens + codeTokens).rounded())
    }

    /// Apply the content-aware estimate across all dialogue text in a conversation.
    private func estimateDialogueTokens(_ conversation: Conversation) -> Int {
        var total = 0
        for msg in conversation.displayMessages {
            switch msg {
            case .userText(let m):
                if !m.isCompactSummary { total += ContextMetrics.estimateTokens(for: m.text) }
            case .assistantText(let m):
                if !m.isApiError { total += ContextMetrics.estimateTokens(for: m.text) }
            default:
                break
            }
        }
        return total
    }

    private func computeBreakdown(
        conversation: Conversation,
        peak: Int,
        window: Int
    ) -> Result.Breakdown {
        var userChars = 0
        var assistantChars = 0
        var toolCallChars = 0
        var toolResultChars = 0
        var systemChars = 0

        for msg in conversation.displayMessages {
            switch msg {
            case .userText(let m):
                userChars += m.text.count
            case .assistantText(let m):
                assistantChars += m.text.count
            case .toolInteraction(let i):
                toolCallChars += i.toolCall.summary.count
                if let r = i.toolResult { toolResultChars += r.resultText.count }
            case .toolCall(let m):
                toolCallChars += m.summary.count
            case .toolResult(let m):
                toolResultChars += m.resultText.count
            case .systemMessage(let m):
                systemChars += m.content.count
            case .compactBoundary:
                break
            }
        }

        let user = userChars / 4
        let assistant = assistantChars / 4
        let tools = toolCallChars / 4
        let results = toolResultChars / 4
        let system = systemChars / 4
        let known = user + assistant + tools + results + system
        let overhead = max(0, peak - known)
        let free = max(0, window - peak)

        return Result.Breakdown(
            userMessages: user,
            assistantMessages: assistant,
            toolCalls: tools,
            toolResults: results,
            system: system,
            overhead: overhead,
            free: free
        )
    }
}

// MARK: - Formatting helpers

extension Int {
    /// "437.5k" / "1.2M" / "512" — matches Claude Code's /context display.
    var formattedTokenCount: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
        if self >= 1_000 {
            let k = Double(self) / 1_000
            if k >= 100 { return String(format: "%.0fk", k) }
            return String(format: "%.1fk", k)
        }
        return "\(self)"
    }
}

extension Double {
    /// "$0.42" / "$12.38" — always two decimal places for small, clean for large.
    var formattedCost: String {
        if self < 0.01 { return "<$0.01" }
        if self < 10 { return String(format: "$%.2f", self) }
        return String(format: "$%.1f", self)
    }
}
