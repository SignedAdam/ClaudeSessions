# Cycle 26 — Restore-from-backup UI (P1.T06)

**Task:** Browse every file in `~/.ClaudeSessions/backup/projects/` and restore any conversation back into Claude Code's project tree.

## What I built

Two new files, both pretty self-contained:

### `Services/BackupVaultService.swift`

Filesystem-based scanner. Walks the backup mirror (no manifest dependency) and produces `Entry` rows:

```
Entry {
    projectSlug
    sessionId
    isSnapshot          // true for .orig-<ts> files
    snapshotTimestamp
    backupPath, size, modifiedAt
    sourceExists        // does ~/.claude/projects/<slug>/<id>.jsonl still exist?
}
```

`listEntries()` returns all entries sorted with missing-source first (the most likely restore targets). `groupBySession()` collapses snapshots onto the same group as their live entry. `restore(entry:)` copies the backup back into the source tree, refusing to overwrite if a file already exists at the target path.

### `Views/BackupVaultView.swift`

720×540 sheet. Layout:

- Header: tray icon + "Backup Vault" title + caption.
- Controls strip: search box, "Only missing originals" toggle, Refresh button.
- Group list: one card per session, with status pill (`source deleted` if applicable), then a sub-list of versions (live mirror + each `.orig` snapshot) each with size, last-modified, and a Restore button.
- Footer: count + "Reveal in Finder" jump.
- Confirmation alert before restore explains exactly where the file will go and refuses if the target already exists.

Wiring: new `appState.showBackupVaultSheet` flag, new sheet in `ContentView`, new `tray.full` icon in the sidebar footer (next to Archive and the show-hidden toggle).

## Design notes

- **Filesystem-based, not manifest-based.** Even if the manifest is corrupt or missing, the user can still browse and restore. The `sourceExists` info is computed from `FileManager.fileExists(atPath:)` on the original path.
- **Snapshots are first-class.** `.orig-<ts>` files appear in the list with their rotation timestamp parsed out of the filename.
- **No "open as preview" yet.** The task description mentioned "open or restore". Restore is the primary case; opening for preview without restoring would mean teaching the conversation viewer to read from outside `~/.claude/projects/`. Filing as a polish follow-up — the user can already restore-then-open or open the file in Finder.
- **No conflict-resolution UI.** If the original still exists, restore is refused with a message telling the user how to proceed manually. This is conservative on purpose — automatic overwrite has too high a blast radius for a defensive feature.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Services/BackupVaultService.swift`
- New: `Sources/ClaudeSessions/Views/BackupVaultView.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (`showBackupVaultSheet` flag)
- Edit: `Sources/ClaudeSessions/ContentView.swift` (sheet)
- Edit: `Sources/ClaudeSessions/Views/Sidebar/SidebarView.swift` (footer button)
- Edit: `docs/STAGE_2_ROADMAP.md` — T06 → done, **Phase 1 complete**.
