# Cycle 73 — Scan Locations settings panel (P10.T03)

**UI for the store from cycle 72.** Still no scanner integration — that lands in T04.

## Layout

A new "Locations" tab between Backup and Claude Code. Each scan root is a stacked tile with:

- **Default root** — house icon (accent), "default" pill, no remove button. Always first.
- **Custom roots** — folder icon, minus.circle remove button, in insertion order.

Both show the basename, full path (monospaced, middle-truncated), and a quick stat ("N project folders") computed by counting non-hidden top-level subdirectories — cheap and synchronous, runs each render. The folder count is good enough to confirm "yes, this is a real Claude projects directory" without doing the full scan.

## Add flow

`Add location…` button → `NSOpenPanel` (directories only, single selection). On `.OK`, calls `scanRootStore.addRoot(url)`. The store returns `nil` on success or a human-readable reason on rejection (not-a-dir / unreadable / duplicate / is-default), which renders inline in red next to the button.

## Footer caveat

> Adding a location only changes what the app *reads*. The continuous backup mirror still watches the default root only — pointing the app at a backup folder won't double-mirror it.

This is the cycle 71 audit decision made visible. Users adding a backup mount as a scan root would otherwise reasonably expect we'd also mirror it.

## Build status

`swift build` clean.

## Files changed

- `Sources/ClaudeSessions/Views/Settings/ScanLocationsSettingsView.swift` (new).
- `Sources/ClaudeSessions/Views/Settings/SettingsView.swift` — added Locations tab between Backup and Claude Code.
- `docs/STAGE_2_ROADMAP.md` — P10.T03 → done.
