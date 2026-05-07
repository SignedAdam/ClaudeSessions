# Cycle 01 — Keyboard Shortcuts & Cleanup

## What Was Done in Cycle 00
- Rewrote MarkdownRenderer with full block-level parsing
- Now handles: headers (H1-H3), bullet lists, numbered lists, blockquotes, horizontal rules, code blocks, paragraphs
- Each block type has proper visual treatment (sizing, indentation, colors)
- Inline markdown still handled by AttributedString

## Focus This Cycle
1. **Keyboard shortcuts** — wire up Cmd+J (JSON toggle), Cmd+F (search focus), Cmd+1 (sidebar toggle)
2. **Clean up dead files** — ProjectRow.swift is empty placeholder
3. **Add keyboard shortcut for Cmd+S** (save — placeholder for now, actual save coming later)
4. **Scroll to top on conversation change**
5. **Add loading spinner when switching conversations**

## What NOT to Do
- Don't start on editing yet — that's a bigger feature
- Don't add AI search implementation yet
- Don't add export — save that for after editing is solid

## Design Thoughts
- Keyboard shortcuts should use `.keyboardShortcut()` modifier on buttons
- Cmd+J should toggle JSON mode even when no button is focused
- Cmd+F should focus the sidebar search field
- Need to think about how to handle Cmd+1 for sidebar toggle in NavigationSplitView
