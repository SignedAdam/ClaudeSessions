# Markdown Rendering Specification

## Approach

Use Swift's built-in `AttributedString(markdown:)` as the primary renderer with custom styling applied via `AttributeContainer`. For elements that `AttributedString` doesn't support well (code blocks, tables), use a custom parser that produces styled `Text` views.

**Do NOT use a WebView/WKWebView.** Keep it native SwiftUI for performance and consistency.

## Supported Markdown Elements

### Headers
```markdown
# H1 — 22pt, bold, primary text color
## H2 — 18pt, semibold, claude accent color
### H3 — 16pt, semibold, primary text color
```
Each header has 8pt top margin and 4pt bottom margin.

### Emphasis
```markdown
**bold** — semibold weight
*italic* — italic style
***bold italic*** — semibold + italic
```

### Code
```markdown
`inline code` — SF Mono 13pt, subtle background (rgba white 0.08), 3pt horizontal padding, 2pt corner radius
```

Code blocks:
````markdown
```python
def foo():
    pass
```
````
- SF Mono 13pt
- Dark background (`rgba(0, 0, 0, 0.3)`)
- 1px border (`var(--border)`)
- 6pt corner radius
- 10pt padding
- Horizontal scroll if content overflows
- Language label in top-right corner (muted text)

### Lists
```markdown
- Unordered item — bullet character + 16pt left indent
1. Ordered item — number + period + 16pt left indent
```
Nested lists: additional 16pt indent per level.

### Blockquotes
```markdown
> Quoted text — 3pt left border in border color, 12pt left padding, muted text color
```

### Links
```markdown
[link text](url) — user accent color, underline on hover, opens in default browser
```

### Tables
```markdown
| Header | Header |
|--------|--------|
| Cell   | Cell   |
```
- Render as a simple grid with border separators
- Header row in semibold
- Muted border between cells
- If table is too wide, horizontal scroll

### Horizontal Rules
```markdown
---
```
1px line in border color, 12pt vertical margin.

### Line Breaks
Preserved. Single newline = `<br>`. Double newline = paragraph break (8pt margin).

## Implementation Strategy

```swift
struct MarkdownRenderer {
    
    /// Render markdown string to a SwiftUI View.
    /// Strategy: split the markdown into segments, render each appropriately.
    @ViewBuilder
    static func render(_ markdown: String) -> some View {
        // 1. Extract code blocks first (``` ... ```)
        //    Replace them with placeholders in the text
        // 2. Render the remaining text using AttributedString(markdown:)
        //    with custom attribute containers for styling
        // 3. For each code block placeholder, insert a CodeBlockView
        // 4. Compose all segments vertically in a VStack
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color("border"), lineWidth: 1)
        )
    }
}
```

## Performance Considerations

- **Lazy rendering:** Don't render markdown for off-screen messages. Use `LazyVStack` and render on appear.
- **Caching:** Cache rendered `AttributedString` per message ID. Invalidate on edit.
- **Long messages:** Some Claude responses are 1000+ words. The rendering must not block the main thread. Use `Task` to render in the background if needed.

## ASCII Art & Diagrams

Claude often produces ASCII art in code blocks:
```
Tyramine ──→ displaces NE ──→ floods synapse
```

These MUST render in monospace font with correct alignment. Use `Text` with `.monospaced()` inside code blocks.

## Edge Cases

- **Empty markdown:** Render nothing (don't show a blank card)
- **Only whitespace:** Render nothing
- **Very long code blocks (>100 lines):** Render with max height and scroll
- **Nested markdown in blockquotes:** Support basic nesting (bold/italic inside quotes)
- **HTML in markdown:** Don't render HTML tags. Show them as escaped text.
- **Emoji:** Render natively (system emoji support)
- **RTL text:** Support via system text layout (no special handling needed)
