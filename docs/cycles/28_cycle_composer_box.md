# Cycle 28 — Composer box (P2.T02)

**Task:** Multi-line input at the bottom of the conversation view, Send button, ⌘↩ submit, disabled while a previous send is in-flight, hidden in JSON mode.

## What I built

### `Views/Conversation/ComposerView.swift`

- Themed text editor (32pt min, 140pt max). Placeholder overlay since `TextEditor` doesn't have one built-in — disappears when text is non-empty.
- Subtle accent border on focus, plain border otherwise.
- Send button: `arrow.up.circle.fill` icon when idle; spinner when in-flight; dimmed when text is empty.
- Hidden ⌘↩ shortcut bound to a zero-size hidden `Button` overlay so it works anywhere in the conversation pane regardless of editor focus.
- Tooltip on the send button explains state ("Send (⌘↩)" / "Type something to send").

### `AppState`

- `composerText: String` — bound to the editor.
- `isComposerSending: Bool` — drives the disabled / spinner state.
- `embeddedChatEnabled: @AppStorage` — global toggle, default true. Settings UI for it lands in P2.T06.
- `submitComposer()` — locks the composer, clears text, shows a "not wired yet" toast, releases after 1.5s. Real subprocess plumbing lands in P2.T03.

### `ConversationContainerView`

- Added `ComposerView()` after `ConversationView` inside the same VStack, gated on `!isJSONMode && embeddedChatEnabled`. JSON mode keeps its full-height editor.

## Notes / not done

- The submit handler is intentionally a stub. Tested manually: typing + ⌘↩ shows the toast, button click does the same, in-flight state replaces the icon with a spinner for 1.5s before re-enabling.
- iMessage mode and document mode both render the composer the same way — the conversation background flows behind it; the composer itself draws its own surface tinted bar.
- No keyboard handling for "shift+enter newline vs enter submit". `TextEditor` accepts Return as newline by default; ⌘↩ is the explicit submit. That matches Slack/Linear conventions.

## Build status

`swift build` clean.

## Files changed

- New: `Sources/ClaudeSessions/Views/Conversation/ComposerView.swift`
- Edit: `Sources/ClaudeSessions/AppState.swift` (state + stub)
- Edit: `Sources/ClaudeSessions/Views/Conversation/ConversationContainerView.swift` (mount the composer)
- Edit: `docs/STAGE_2_ROADMAP.md` — T02 → done
