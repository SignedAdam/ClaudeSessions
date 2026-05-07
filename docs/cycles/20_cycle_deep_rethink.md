# Cycle 20 — Deep Rethink: What Should This App Actually Be?

## What Claude Code Is
Claude Code is a CLI coding agent. But people use it for WAY more than code:
- Research (nootropics, science, business strategy)
- Writing (docs, specs, creative work)
- Analysis (data, architecture, decisions)
- Planning (projects, features, approaches)
- Learning (new technologies, concepts, deep dives)

Every one of these conversations is **knowledge** that gets buried in JSONL files. The app should make this knowledge accessible, reusable, and actionable.

## What This App Should Be: A Knowledge Manager for Claude Conversations

### Core Identity
Not just a "viewer" — a **session manager and knowledge extractor**. The name "Claude Sessions" is right. It's where you go to:
1. Find that conversation where you figured out X
2. Extract the good parts and use them again
3. Continue where you left off
4. See what you've been working on across projects

### Features That Make It Maximally Useful

**Already have (needs polish):**
- Browse/read conversations
- Edit messages
- Save with backup
- Export as prompt
- AI search
- Open in CLI

**Must add:**
1. **"Quick Extract" — one-click prompt extraction**
   - Button per conversation: "Extract Prompts" → instantly copies just the human+Claude dialogue
   - "Extract & Open in Claude" → extracts + launches new claude session with it piped in
   - These should be THE fastest possible workflow

2. **Token/cost tracking per conversation**
   - Show input/output tokens per message
   - Total cost estimate per conversation
   - Cost per project aggregation

3. **Conversation timeline view**
   - Visual timeline of when conversations happened
   - See patterns: "I worked on Narkis every evening this week"

4. **Pin/star conversations**
   - Mark important ones for quick access
   - Pinned section at top of sidebar

5. **Conversation summary generation**
   - One-click "summarize this conversation" using the AI search infrastructure
   - Store summaries for faster browsing

6. **Message-level bookmarks**
   - Bookmark specific Claude responses that were particularly good
   - Quick-access list of bookmarked messages

7. **Diff view between conversation versions**
   - When you've edited + saved, show what changed

8. **Statistics dashboard**
   - Total conversations, tokens used, most active projects
   - Daily/weekly usage charts
   - Most used tools breakdown

9. **Drag & drop messages**
   - Drag a Claude response directly into another app
   - Drag a code block into your editor

10. **"Continue conversation" with context injection**
    - Select specific messages from an old conversation
    - Open new Claude Code session with just those messages as context
    - More surgical than full export

## Design Vision
The current colors are wrong. The app should feel like:
- **VS Code's dark theme** — comfortable, professional, not "hacker"
- **Linear** — clean, minimal, fast
- **Arc browser** — modern macOS aesthetic

Colors should be:
- Subtle, not garish
- User messages: barely tinted, almost neutral
- Claude messages: slightly different background, not purple
- Tool calls: compact, muted, collapsed by default
- The focus should be on TEXT READABILITY above all

## What NOT to Build
- Chat input — this isn't a Claude client
- Anything that modifies Claude Code's internals
- Complex database/indexing — keep it file-based
- Social/sharing features
