# Cycle 02 — Message Editing

## Focus
Implement in-place message editing for user and Claude messages. This is a core spec feature (Task 9).

## Design
1. Hover on any user/Claude message shows a pencil icon
2. Click pencil → message body becomes a TextEditor
3. Done/Cancel buttons appear
4. Only one message editable at a time
5. Edits update the in-memory Conversation model
6. isDirty flag set → toolbar shows "Unsaved Changes"
7. No disk writes yet (that's save/backup cycle)

## Implementation Plan
- Add `editingMessageId` tracking to AppState (already exists)
- Add `editedTexts: [String: String]` dict to AppState to track pending edits
- Modify UserMessageView and AssistantMessageView to show pencil on hover
- When editing: swap Text/MarkdownRenderer for TextEditor
- Done commits edit to `editedTexts` dict and sets isDirty
- Cancel reverts
- Starting new edit auto-commits current one

## What NOT to Do
- Don't implement save-to-disk yet
- Don't implement delete messages yet
- Don't try to edit tool calls/results (spec says JSON mode only for those)
- Don't add undo/redo beyond cancel
