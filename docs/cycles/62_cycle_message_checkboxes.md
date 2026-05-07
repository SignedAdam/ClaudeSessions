# Cycle 62 — Message-row checkboxes (P8.T03)

**Task:** Add a leading-edge checkbox next to each selectable message when select mode is active.

## What I built

### `Views/Conversation/MessageSelectionCheckbox.swift`

Tiny standalone view: 22×22 button with `checkmark.circle.fill` (accent) when selected, `circle` (textTertiary) otherwise. Tap calls `appState.toggleSelection(messageId:)`. Help text describes the action.

### `UserMessageView` / `AssistantMessageView`

Both restructured the same way: extracted the body's existing branches into `messageContent` (a `@ViewBuilder` private property), and the public `body` now wraps that content in an HStack with the checkbox prefix when `appState.isSelectMode` is true. Compact-summary and deleted variants don't get a checkbox — they're not selectable.

The pattern is symmetric across both files so future additions (e.g. ToolInteractionView in select mode) can follow the same recipe.

## Why a wrapping HStack rather than overlay

The check needs to push content right when active, not float over it. Overlay would partially cover the message text or the leading accent strip. The HStack adds a clean 30pt-ish gutter only when select mode is active.

## Hover button interaction

The hover-only edit/copy buttons live as `.overlay(alignment: .topTrailing)` on the right side of each message. They keep working as before — checkbox is on the left, hover buttons on the right, no overlap. No need to disable them in select mode.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Views/Conversation/MessageSelectionCheckbox.swift`
- Edit: `Sources/ClaudeSessions/Views/Conversation/UserMessageView.swift` (body wrap, messageContent extraction)
- Edit: `Sources/ClaudeSessions/Views/Conversation/AssistantMessageView.swift` (same)
- Edit: `docs/STAGE_2_ROADMAP.md` — T03 → done
