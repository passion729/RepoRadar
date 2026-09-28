import SwiftUI

/// Block-level GitHub-flavored markdown: headings, lists, task lists, quotes, code and tables.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `marker` is "•", "1.", "☐" or "☑"; `depth` counts nesting levels.
    case listItem(marker: String, depth: Int, text: String)
    case quote(String)
    case code(String)
    case table([[String]])
    case rule

    // ponytail: line-based block parser covering what PR/issue bodies use; no nested quotes, setext
    // headings or lazy continuation lines. Switch to swift-cmark if those start showing up.
    static func parse(_ source: String) -> [MarkdownBlock] {
        let cleaned = source.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        let lines = cleaned.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }

            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
            } else if let match = trimmed.firstMatch(of: /^(#{1,6})\s+(.*?)\s*#*$/) {
                flushParagraph()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
            } else if trimmed.firstMatch(of: /^([-*_])(\s*\1){2,}$/) != nil {
                flushParagraph()
                blocks.append(.rule)
            } else if let match = trimmed.firstMatch(of: /^[-*+]\s+\[([ xX])\]\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: match.1 == " " ? "☐" : "☑", depth: indent / 2, text: String(match.2)))
            } else if let match = trimmed.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: "•", depth: indent / 2, text: String(match.1)))
            } else if let match = trimmed.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: "\(match.1).", depth: indent / 2, text: String(match.2)))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: " ")))
                continue
            } else if trimmed.hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = lines[index].trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                        .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !cells.allSatisfy({ $0.firstMatch(of: /^:?-+:?$/) != nil }) { rows.append(cells) }  // skip |---|
                    index += 1
                }
                blocks.append(.table(rows))
                continue
            } else if indent >= 2, case .listItem(let marker, let depth, let text)? = blocks.last, paragraph.isEmpty {
                blocks[blocks.count - 1] = .listItem(marker: marker, depth: depth, text: text + " " + trimmed)  // wrapped item
            } else {
                paragraph.append(trimmed)
            }
            index += 1
        }
        flushParagraph()
        return blocks
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct MarkdownText: View {
    let blocks: [MarkdownBlock]

    init(_ source: String) { blocks = MarkdownBlock.parse(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { index in
                block(blocks[index])
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func block(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownBlock.inline(text))
                .themeFont(level == 1 ? .title2 : level == 2 ? .title3 : .headline, weight: .bold)
                .padding(.top, level <= 2 ? 6 : 2)
            if level <= 2 { Divider() }
        case .paragraph(let text):
            Text(MarkdownBlock.inline(text))
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 14, alignment: .trailing)
                Text(MarkdownBlock.inline(text))
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            Text(MarkdownBlock.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code).themeFont(.callout, mono: true).padding(10)
            }
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row].indices, id: \.self) { column in
                            Text(MarkdownBlock.inline(rows[row][column])).fontWeight(row == 0 ? .semibold : .regular)
                        }
                    }
                    if row == 0 { Divider() }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }
}
