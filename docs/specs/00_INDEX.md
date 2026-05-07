# Claude Sessions — Specification Index

## Documents

| # | File | Description |
|---|------|-------------|
| 01 | [OVERVIEW](01_OVERVIEW.md) | What the app is, core principles, feature set, future work |
| 02 | [DATA_MODEL](02_DATA_MODEL.md) | Complete JSONL format reference — every entry type, every field, with examples |
| 03 | [ARCHITECTURE](03_ARCHITECTURE.md) | Tech stack, file structure, data flow, window layout ASCII diagram |
| 04 | [UX_AND_DESIGN](04_UX_AND_DESIGN.md) | Colors, typography, layout, interactions, keyboard shortcuts, empty states, animations |
| 05 | [FEATURES_DETAIL](05_FEATURES_DETAIL.md) | Detailed specs for all 10 features (discovery, rendering, copy, edit, save, JSON mode, export, AI search, open in CLI, backup) |
| 06 | [SWIFT_MODELS](06_SWIFT_MODELS.md) | Complete Swift Codable type definitions for all JSONL entry types + display models |
| 07 | [IMPLEMENTATION_TASKS](07_IMPLEMENTATION_TASKS.md) | 17 ordered implementation tasks, each with deliverables and acceptance criteria |
| 08 | [EDGE_CASES](08_EDGE_CASES.md) | Error handling, malformed data, concurrent edits, file conflicts, permission issues |
| 09 | [AI_SEARCH_SPEC](09_AI_SEARCH_SPEC.md) | OpenRouter integration: API format, prompt design, error handling, UI states, privacy |
| 10 | [MARKDOWN_RENDERING](10_MARKDOWN_RENDERING.md) | Markdown → native SwiftUI rendering strategy, supported elements, performance |
| 11 | [CRITICAL_DETAILS](11_CRITICAL_DETAILS.md) | Lossless round-tripping, tool pairing algorithm, project name derivation, file watching, Keychain, terminal launch |

## Quick Start for Implementation

1. Read `01_OVERVIEW.md` for the big picture
2. Read `03_ARCHITECTURE.md` for the app structure
3. Read `06_SWIFT_MODELS.md` for the data types (implement these first)
4. Follow `07_IMPLEMENTATION_TASKS.md` sequentially — each task builds on the previous
5. Reference `02_DATA_MODEL.md` when debugging parsing issues
6. Reference `04_UX_AND_DESIGN.md` for visual decisions
7. Reference `08_EDGE_CASES.md` when handling errors

## Key Data Paths

- Conversations: `~/.claude/projects/<project-slug>/<session-uuid>.jsonl`
- Session index: `~/.claude/projects/<project-slug>/sessions-index.json`
- Subagent chats: `~/.claude/projects/<project-slug>/<session-uuid>/subagents/agent-<id>.jsonl`
- Backups (created by this app): `~/.claude-sessions-backups/<session-id>/<timestamp>.jsonl`

## Real Data Stats (from user's machine)

- 22 project directories in `~/.claude/projects/`
- 6 projects have a `sessions-index.json` (130 indexed sessions)
- 94 JSONL conversation files not in any index
- Largest conversation: 4.0 MB, 592 JSONL lines
- Most active project: `shortimize-backend` (98 sessions)
- Entry types by frequency: assistant (443), user (338), file-history-snapshot (146), queue-operation (38), system (46), progress (26)
- Tool names found: Bash, Read, Write, Edit, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskOutput, ToolSearch, WebSearch, ExitPlanMode
