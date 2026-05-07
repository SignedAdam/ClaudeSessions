import SwiftUI

struct MarkdownRenderer: View {
    let text: String

    /// Over this threshold we don't even try to parse markdown. The value is
    /// intentionally modest — most real messages are under 10k characters.
    /// For anything larger, the parse + layout cost just isn't worth the
    /// styling. Plain text is still fully readable and selectable.
    private static let maxCharsForMarkdown = 10_000

    /// Three parse states. We START in `.pending` and render plain text; a
    /// `.task(id: text)` kicks off parsing on a background thread; on
    /// completion we upgrade to `.parsed(blocks)`. This guarantees `body`
    /// never blocks on a synchronous parse — even on first render.
    private enum State {
        case pending
        case parsed([Block])
        case tooLarge
    }

    @SwiftUI.State private var state: State = .pending
    @SwiftUI.State private var parsedTextKey: String = ""

    var body: some View {
        content
            .task(id: text) {
                await reparse()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .pending:
            // Placeholder while the background parse runs. Plain text is
            // cheap to render and still fully legible.
            plainText

        case .tooLarge:
            plainText

        case .parsed(let blocks):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
        }
    }

    private var plainText: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.text)
            .textSelection(.enabled)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Run parsing off the main actor. If text is too large OR the view
    /// gets replaced (task id changes) this simply exits; we can then
    /// re-enter for the new text value.
    private func reparse() async {
        // Short-circuit the "nothing changed" case.
        if parsedTextKey == text, case .parsed = state { return }

        if text.count > Self.maxCharsForMarkdown {
            state = .tooLarge
            parsedTextKey = text
            return
        }

        let current = text
        let blocks = await Task.detached(priority: .userInitiated) {
            MarkdownRenderer.parseBlocksStatic(current)
        }.value

        // Task.id cancellation happens implicitly when text changes — SwiftUI
        // cancels the old .task. We still guard in case we lost the race.
        guard current == text else { return }
        state = .parsed(blocks)
        parsedTextKey = text
    }

    // MARK: - Block Types

    fileprivate enum Block {
        case paragraph(String)
        case heading(Int, String)       // level, text
        case codeBlock(String, String?) // code, language
        case bulletList([String])
        case numberedList([String])
        case blockquote(String)
        case horizontalRule
        case empty
    }

    // MARK: - Block Parsing (static so it can run on a detached task)

    nonisolated fileprivate static func parseBlocksStatic(_ text: String) -> [Block] {
        parseBlocksImpl(text)
    }

    nonisolated private static func parseBlocksImpl(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language = lang.isEmpty ? nil : lang
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n"), language))
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            if isBulletItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBulletItem(t) {
                        items.append(stripBullet(t))
                        i += 1
                    } else if t.isEmpty {
                        i += 1
                        break
                    } else if !items.isEmpty && (lines[i].hasPrefix("  ") || lines[i].hasPrefix("\t")) {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items))
                continue
            }

            if isNumberedItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if isNumberedItem(t) {
                        items.append(stripNumber(t))
                        i += 1
                    } else if t.isEmpty {
                        i += 1
                        break
                    } else if !items.isEmpty && (lines[i].hasPrefix("  ") || lines[i].hasPrefix("\t")) {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numberedList(items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        let content = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content)
                        i += 1
                    } else if t.isEmpty {
                        i += 1
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Paragraph
            var paraLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") || t.hasPrefix("#") ||
                   isBulletItem(t) || isNumberedItem(t) || t.hasPrefix(">") ||
                   isHorizontalRule(t) {
                    break
                }
                paraLines.append(lines[i])
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    // MARK: - Helpers (static for off-main parsing)

    nonisolated private static func parseHeading(_ line: String) -> Block? {
        if line.hasPrefix("### ") { return .heading(3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ")  { return .heading(2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ")   { return .heading(1, String(line.dropFirst(2))) }
        return nil
    }

    nonisolated private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return (stripped.allSatisfy { $0 == "-" } && stripped.count >= 3) ||
               (stripped.allSatisfy { $0 == "*" } && stripped.count >= 3) ||
               (stripped.allSatisfy { $0 == "_" } && stripped.count >= 3)
    }

    nonisolated private static func isBulletItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    nonisolated private static func stripBullet(_ line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.dropFirst(2))
        }
        return line
    }

    nonisolated private static func isNumberedItem(_ line: String) -> Bool {
        guard let dotIdx = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIdx]
        guard prefix.allSatisfy(\.isNumber), !prefix.isEmpty else { return false }
        let afterDot = line.index(after: dotIdx)
        return afterDot < line.endIndex && line[afterDot] == " "
    }

    nonisolated private static func stripNumber(_ line: String) -> String {
        guard let dotIdx = line.firstIndex(of: ".") else { return line }
        let afterDot = line.index(after: dotIdx)
        guard afterDot < line.endIndex else { return line }
        return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            renderInlineMarkdown(text).padding(.bottom, 6)

        case .heading(let level, let text):
            renderHeading(level: level, text: text)

        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language).padding(.vertical, 4)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        renderInlineMarkdown(item)
                    }
                }
            }
            .padding(.leading, 4).padding(.bottom, 6)

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            .frame(width: 20, alignment: .trailing)
                        renderInlineMarkdown(item)
                    }
                }
            }
            .padding(.leading, 2).padding(.bottom, 6)

        case .blockquote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent.opacity(0.3))
                    .frame(width: 3)
                renderInlineMarkdown(text)
                    .foregroundStyle(Theme.textSecondary)
                    .italic()
                    .padding(.leading, 10)
            }
            .padding(.vertical, 4)

        case .horizontalRule:
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 8)

        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        let (size, weight, color): (CGFloat, Font.Weight, Color) = {
            switch level {
            case 1: return (20, .bold, Theme.text)
            case 2: return (17, .semibold, Theme.accent)
            default: return (15, .semibold, Theme.text)
            }
        }()

        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .padding(.top, level == 1 ? 10 : 6)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func renderInlineMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )) {
            Text(attributed)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .tint(Theme.humanTint)
                .lineSpacing(3)
        } else {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .lineSpacing(3)
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    /// Same principle as MarkdownRenderer: a thousand-line code block in
    /// a single Text view makes SwiftUI layout very slow. Cap the visible
    /// height and let the user scroll.
    private static let maxCodeLines = 200

    private var displayCode: String {
        let cleaned = code.hasSuffix("\n") ? String(code.dropLast()) : code
        let lines = cleaned.components(separatedBy: "\n")
        if lines.count > Self.maxCodeLines {
            return lines.prefix(Self.maxCodeLines).joined(separator: "\n")
                + "\n\n[… \(lines.count - Self.maxCodeLines) more lines truncated — click copy for full content]"
        }
        return cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language {
                    Text(lang)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? Theme.toolTint : Theme.textSecondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayCode)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.border.opacity(0.6), lineWidth: 1)
        )
    }
}
