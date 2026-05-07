import Foundation

struct AISearchService {
    struct SearchResult {
        let sessionIds: [String]
    }

    enum SearchError: LocalizedError {
        case noApiKey
        case invalidResponse
        case httpError(Int, String)
        case timeout
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "Configure your OpenRouter API key in Settings to use AI Search."
            case .invalidResponse: return "Unexpected response format. Try a different query."
            case .httpError(let code, let msg):
                switch code {
                case 401: return "Invalid API key. Check your OpenRouter key in Settings."
                case 402: return "Insufficient credits on your OpenRouter account."
                case 429: return "Rate limited. Wait a moment and try again."
                default: return "API error (\(code)): \(msg)"
                }
            case .timeout: return "Search timed out after 30 seconds."
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            }
        }
    }

    func search(query: String, conversations: [(id: String, summary: String, firstPrompt: String?, project: String, date: String)]) async throws -> SearchResult {
        guard let apiKey = KeychainService.load(), !apiKey.isEmpty else {
            throw SearchError.noApiKey
        }

        let model = UserDefaults.standard.string(forKey: "openRouterModel") ?? "anthropic/claude-sonnet-4"

        // Build conversation list for the prompt
        let conversationList = conversations.map { conv in
            var obj: [String: String] = [
                "id": conv.id,
                "project": conv.project,
                "date": conv.date
            ]
            obj["summary"] = conv.summary
            if let fp = conv.firstPrompt {
                obj["firstPrompt"] = String(fp.prefix(100))
            }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "{\"id\":\"\(conv.id)\"}"
        }.joined(separator: "\n")

        let systemPrompt = "You are a search assistant for Claude Code conversation histories. Given a user's search query and a list of conversation summaries, return a JSON array of session IDs that match the query, ranked by relevance (most relevant first). Return ONLY the JSON array, no explanation.\n\nExample response: [\"abc-123\", \"def-456\"]"

        let userMessage = "Query: \"\(query)\"\n\nConversations:\n\(conversationList)"

        // Build request
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Claude Sessions", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SearchError.timeout
        } catch {
            throw SearchError.networkError(error)
        }

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SearchError.httpError(httpResponse.statusCode, body)
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SearchError.invalidResponse
        }

        // Parse the JSON array from content
        guard let contentData = content.data(using: .utf8),
              let ids = try? JSONSerialization.jsonObject(with: contentData) as? [String] else {
            throw SearchError.invalidResponse
        }

        return SearchResult(sessionIds: ids)
    }
}
