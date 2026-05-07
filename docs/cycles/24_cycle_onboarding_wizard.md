# Cycle 24 — First-run onboarding wizard (P1.T04)

**Task:** Single-page modal shown on first launch with two recommendations: extend `cleanupPeriodDays`, install the backup LaunchAgent.

## What I did

New file: `Sources/ClaudeSessions/Views/Onboarding/OnboardingView.swift` (~190 lines).

- **Header:** shield icon + "Welcome to Claude Sessions" + one-line explainer.
- **Card 1 — Extend session retention:** explains the 30-day default cleanup and offers "Set to 36500 days" / "Skip". Uses `ClaudeCodeConfigStore` (existing service from the Claude Code Settings tab) so the write path is shared.
- **Card 2 — Install the background backup daemon:** explains the protection and offers "Install LaunchAgent" / "Skip". Calls `LaunchAgentInstaller.install()` off the main thread so the UI can show a spinner. On failure, displays the underlying error (monospaced, in error tint) and shows "Retry" + "Skip".
- **Per-card state machine:** `pending` → `applying` → `applied` / `skipped` / `failed`. Each state renders different controls (skip+apply, spinner, checkmark, retry+skip).
- **Footer:** small reassurance ("you can change either of these later in Settings") + Done button. Done sets `didShowOnboarding=true` in `UserDefaults` and dismisses.

Wired into `ContentView`:
- `@AppStorage("didShowOnboarding")` flag.
- `@State` boolean to actually drive the sheet (we set it from the `.task` after `loadProjects` so the window is on screen first).
- `.sheet(isPresented: $presentOnboarding) { OnboardingView() ... }`.

Theming uses the same primitives as the rest of the app: `Theme.surface` background, `Theme.surface2` for card backgrounds, `Theme.accent` for icons, `Theme.successTint` / `Theme.errorTint` / `Theme.textTertiary` for state cues. Cards are rounded-rectangle bordered, matching the look of e.g. the Settings sections.

## Build status

`swift build` clean. Both targets still compile.

## Behavioral note

- On a fresh machine (no `didShowOnboarding` key), the wizard appears after the projects list loads. Skip-skip-Done will close it without changing anything; the user can reopen it later only by deleting the UserDefaults key — there's no in-app re-launch yet.
- A future small improvement: a "Show Onboarding…" button in Settings → General that resets the flag and re-presents the wizard. Filed under polish, not adding now.

## Files changed

- New: `Sources/ClaudeSessions/Views/Onboarding/OnboardingView.swift`
- Edit: `Sources/ClaudeSessions/ContentView.swift` (state + .sheet + .task hook)
- Edit: `docs/STAGE_2_ROADMAP.md` — T04 → done
