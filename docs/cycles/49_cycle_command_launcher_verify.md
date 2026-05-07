# Cycle 49 — `.command` launcher verification (P6.T02)

**Task:** Confirm the universal launcher path is intact end-to-end.

## What I checked

Code-read of `Utilities/ProcessLauncher.swift::launch(command:cwd:)`:

- ✓ Support dir: `~/Library/Application Support/ClaudeSessions/launch/` (created via `FileManager.createDirectory(... withIntermediateDirectories: true)`).
- ✓ Filename: `launch-<UUID>.command` per call.
- ✓ Body: `#!/bin/bash`, `cd '<quoted cwd>' || exit 1`, `<command>`, `exec <user shell> -l`. The trailing `exec` keeps the window alive after the command finishes.
- ✓ Permissions: `0o755` via `setAttributes`.
- ✓ Open: `NSWorkspace.shared.open(scriptURL)`. macOS routes to the user-configured `.command` handler.
- ✓ Cleanup: a `DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 600)` removes the script.

Bash smoke test mirrored the path: created `~/Library/Application Support/ClaudeSessions/launch/launch-test-<pid>.command`, chmod 0755, confirmed `[ -x ... ]` returns true. File system path works.

The actual GUI launch (a terminal window appearing on screen) requires a human at the keyboard — there's no headless way to assert "a Terminal.app/Ghostty/iTerm2 window opened with my script running." But the code path delivering the file to NSWorkspace is unchanged from cycle 22 and the smoke test confirms the file gets onto disk in the expected shape.

## Build status

No code changes — verification only.

## Files changed

- `docs/STAGE_2_ROADMAP.md` — T02 → done
- `docs/cycles/49_cycle_command_launcher_verify.md` — this note
