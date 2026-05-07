# Cycle 71 — Phase 10 audit (P10.T01)

**Research only.** Confirms the multi-root and subagent gaps so the next 6 tasks land cleanly.

## Hardcoded `~/.claude/projects/` references — load-bearing

| File | Line | Role |
|------|------|------|
| `Services/ProjectScanner.swift` | 4-7 | The only structural root. `claudeProjectsPath` is a `let` initialized from `homeDirectoryForCurrentUser`. Must become a list. |
| `Services/VersionHistoryService.swift` | 79 | Builds the `.live` JSONL path for the version history listing. Needs root-aware lookup (project knows its root). |
| `Services/SessionCreator.swift` | 105-115 | Write target for new + restored sessions. cwd → slug → root. The "which root" question is implicit: same root as the source session. |
| `ContinuousBackup/BackupEngine.swift` | 37 | FSEvents watch path. Either remains default-only (simpler) or becomes a list of watched roots. Phase 10 can keep it default-only and treat custom roots as read-only mirrors — the user adding a backup mount doesn't expect the app to start mirroring it again. |

## Doc-comment-only references (not load-bearing)

`AppState.swift:584,878`, `Utilities/SlugResolver.swift:57`, `Views/BackupVaultView.swift:9`, `Views/Settings/BackupSettingsView.swift:69`, `Views/Sidebar/SidebarView.swift:225,439`, `Views/Onboarding/OnboardingView.swift:71,99`, `Services/BackupVaultService.swift:22,106`, `Services/VersionHistoryService.swift:9,20`, `Services/VersionRestoreService.swift:7`, `Services/ArchiveService.swift:3,7`, `Services/MCPTools/MCPOrganizeTools.swift:69`. All comment text. Will need wording updates as we ship multi-root, but they don't gate the work.

## Slug / id collision risk

- `SlugResolver` resolves *cwd from slug* by walking candidate paths and checking FS existence. It does **not** assume a single root, but it also doesn't disambiguate per-root — same slug under two roots would resolve to the same cwd (which is fine: the slug encodes the cwd by design).
- The real collision risk is in **`Project.id`** (`DisplayModels.swift:6`) — currently just the slug string. Two projects with the same slug under different roots would clash in SwiftUI's `ForEach`. Fix: incorporate the root, e.g. `Project.id = "<rootHash>:<slug>"`. Public `name` and `originalPath` stay as-is.
- Cross-root SessionInfo.id collision is theoretically possible (UUID v4 collisions are vanishingly rare, but the same JSONL could legitimately exist under both roots if the user copies it). Same fix applies if it surfaces: prefix with root.

## Subagent surfaces today

- Stitched in by `ProjectScanner.swift:91-126`. The scanner walks `<projectDir>/<parentSessionId>/subagents/agent-*.jsonl` and attaches each to its parent's `SessionInfo.subagents` array.
- Rendered in `SidebarView.swift:384-401`: `ForEach(session.subagents)` indented under the parent row when the parent is expanded.
- `SessionRow.swift:49-54` shows a `sparkle` icon and slightly smaller font when `isSubagent == true`.
- **Gaps**: no agent-name extraction (filename parsing is doable from `agent-<NAME>-<uuid>.jsonl`); no aggregate count anywhere; no cross-project view; subagents are invisible until you expand each parent. T05-T07 close these.

## Decisions for the rest of Phase 10

- **Default root is non-removable.** The settings panel marks it as such.
- **BackupEngine stays default-only.** Custom roots are read-only sources; mirroring an external mount is not implicit. (We can revisit if user demand emerges.)
- **Project.id becomes `rootHash:slug`** in T04. The hash is a stable derivation of the root URL (e.g. `String(URL.absoluteString.hash, radix: 36)`).
- **Sidebar root tag** (T04) only renders when ≥2 roots exist. With one root, the UI is identical to today.
- **Subagent index** (T05+) is computed over the existing scan output — no new I/O.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — P10.T01 → done.
- `docs/cycles/71_cycle_p10_audit.md` — this note.
