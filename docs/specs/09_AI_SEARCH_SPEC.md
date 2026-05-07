# AI Search — Detailed Specification

## Overview

AI Search allows the user to find conversations using natural language queries. It sends conversation metadata to an LLM via OpenRouter and gets back ranked results.

## Architecture

```
User Query
    │
    ▼
SearchViewModel
    │
    ├──► Text Search (instant, local)
    │    └── fuzzy match on title, firstPrompt, project name
    │
    └──► AI Search (async, API call)
         │
         ▼
    AISearchService
         │
         ├── 1. Collect all conversation summaries from cache
         ├── 2. Build prompt with query + summaries
         ├── 3. Call OpenRouter API
         ├── 4. Parse response (JSON array of session IDs)
         └── 5. Return ranked [SessionInfo]
```

## OpenRouter API Integration

### Endpoint
```
POST https://openrouter.ai/api/v1/chat/completions
```

### Headers
```
Authorization: Bearer <api-key>
Content-Type: application/json
HTTP-Referer: https://github.com/sauel/claude-sessions
X-Title: Claude Sessions
```

### Request Body
```json
{
  "model": "<configured-model>",
  "max_tokens": 2048,
  "messages": [
    {
      "role": "system",
      "content": "You are a search assistant for Claude Code conversation histories. Given a user's search query and a list of conversation summaries, return a JSON array of session IDs that match the query, ranked by relevance (most relevant first). Return ONLY the JSON array, no explanation.\n\nExample response: [\"abc-123\", \"def-456\"]"
    },
    {
      "role": "user",
      "content": "Query: \"that conversation about tyramine and cheese\"\n\nConversations:\n{\"id\":\"722e20c8-...\",\"summary\":\"Nootropic Stack Research\",\"firstPrompt\":\"methylene blue in combination with modafinil...\",\"project\":\"dev\",\"date\":\"2026-04-01\"}\n{\"id\":\"25e0280e-...\",\"summary\":\"Conversation Viewer\",\"firstPrompt\":\"hello claude :) could you help me make a viewer...\",\"project\":\"dev\",\"date\":\"2026-04-05\"}\n..."
    }
  ]
}
```

### Response Parsing
```json
{
  "choices": [
    {
      "message": {
        "content": "[\"722e20c8-...\", \"25e0280e-...\"]"
      }
    }
  ]
}
```

Parse `choices[0].message.content` as a JSON array of strings. Match each string against known session IDs. Ignore unknown IDs.

### Error Handling

| HTTP Status | Behavior |
|-------------|----------|
| 200 | Parse response |
| 401 | "Invalid API key. Check your OpenRouter key in Settings." |
| 402 | "Insufficient credits on your OpenRouter account." |
| 429 | "Rate limited. Wait a moment and try again." |
| 500+ | "OpenRouter service error. Try again later." |
| Timeout | "Search timed out after 30 seconds." |
| Parse error | "Unexpected response format. Try a different query." |

## UI

### Search Panel
The search panel appears as a sheet or sidebar overlay when activated (Cmd+Shift+F):

```
┌─ AI Search ────────────────────────────────────┐
│ [🔍 Search conversations...                  ] │
│                                                 │
│ ◉ Text Search   ○ AI Search                   │
│                                                 │
│ Results:                                        │
│ ┌──────────────────────────────────────────┐   │
│ │ 🟣 Nootropic Stack Research              │   │
│ │ dev · Apr 1 · 21 messages                │   │
│ │ "methylene blue in combination with..."  │   │
│ └──────────────────────────────────────────┘   │
│ ┌──────────────────────────────────────────┐   │
│ │ 🟣 MKULTRA-II Project                   │   │
│ │ dev · Apr 5 · 45 messages                │   │
│ └──────────────────────────────────────────┘   │
│                                                 │
│                              [Close]            │
└─────────────────────────────────────────────────┘
```

### States
- **Idle:** Empty search field, no results
- **Typing (text search):** Results update as user types (debounced 200ms)
- **Loading (AI search):** Spinner + "Searching with AI..."
- **Results:** List of matching sessions
- **Error:** Error message with retry button
- **No results:** "No conversations match your query."
- **No API key:** "Configure OpenRouter API key in Settings to use AI Search."

## Text Search (Fallback)

Always available, no API key needed. Searches:
- Session title / summary
- First prompt text
- Project name

Uses case-insensitive substring matching. Results ranked by:
1. Exact match in title (highest)
2. Match in first prompt
3. Match in project name

## Model Configuration

### Default Model
`anthropic/claude-sonnet-4` (good balance of speed and quality for search)

### Preset Models (shown in dropdown)
- `anthropic/claude-sonnet-4` — Recommended
- `anthropic/claude-haiku-4-5` — Fastest, cheapest
- `google/gemini-2.5-flash` — Fast alternative
- `openai/gpt-4o-mini` — Budget option

### Custom Model
Free text field where user can type any OpenRouter model ID.

## Privacy

- Conversation summaries (title + first prompt, ~100 chars each) are sent to the API
- Full conversation content is NEVER sent in v1
- The user controls this — AI search is opt-in via API key configuration
- Display a note in Settings: "AI Search sends conversation titles and first messages to OpenRouter. Full conversation content is never sent."
