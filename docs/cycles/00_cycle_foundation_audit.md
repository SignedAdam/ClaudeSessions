# Cycle 00 — Foundation Audit

## Assessment
The app exists and builds. The core data pipeline works (scan -> parse -> display). The critical bug (clicking sessions did nothing) is fixed. But the app is rough:

1. **Markdown rendering is weak** — it uses `AttributedString(markdown:, interpretedSyntax: .inlineOnlyPreservingWhitespace)` which only handles bold/italic/code/links inline. Headers, bullet lists, numbered lists, blockquotes, and tables get no special visual treatment. Real Claude output is full of these. This is the #1 visual quality issue.

2. **No editing at all** — a core feature of the spec. Without editing + save + backup, this is just a read-only viewer.

3. **Keyboard shortcuts missing** — Cmd+J for JSON toggle, Cmd+F for search, etc. These are easy wins for usability.

4. **No multi-select copy** — single message copy works but multi-select mode isn't wired up.

## Priority for This Cycle
Focus on the **Markdown renderer** — it's the most visually impactful improvement. Real Claude responses have headers, bullet lists, code blocks, blockquotes. If those render well, the app will look dramatically better.

## What to Do
- Rewrite MarkdownRenderer to handle block-level elements:
  - Headers (H1-H3) with proper sizing
  - Bullet and numbered lists with indentation
  - Blockquotes with left border
  - Horizontal rules
  - Better paragraph spacing
- Keep the code block extraction as-is (it works)
- Keep AttributedString for inline formatting within paragraphs

## What NOT to Do
- Don't add external markdown parsing libraries — keep it zero-dependency
- Don't try to render HTML embedded in markdown
- Don't over-engineer — Claude's markdown is fairly standard, not edge-case heavy
- Don't touch the data models or parser this cycle — they work

## Direction
After markdown, the next cycles should tackle: editing, keyboard shortcuts, multi-select, export, save/backup — roughly in that order of user impact.
