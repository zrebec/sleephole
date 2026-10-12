#if DEBUG   // the document is bundled into Debug builds only (project.yml)
import SwiftUI

/// Pure parser for `docs/PREHLAD-PLANOV.md` (the plans overview): headings, paragraphs, bullets, the main table
/// (found by its shape: five header cells, the first one `#`) and the small legend tables.
enum PlansDocument {
    struct Item: Equatable {
        var number: Int?
        var title: String
        var effort: String
        var priority: String
        var done = false
        var summary: String
    }

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case item(Item)
        case legend([String])
    }

    private static func cells(_ line: String) -> [String] {
        var parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" } }
    }

    private static func bulletText(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
        if let dot = trimmed.firstIndex(of: "."), dot != trimmed.startIndex,
           trimmed[..<dot].allSatisfy(\.isNumber), trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
            return trimmed
        }
        return nil
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var inTable = false
        var tableIsMain = false
        var mainDone = false

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }

        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") {
                flush()
                let row = cells(trimmed)
                if !inTable {                                   // the header row of a new table
                    inTable = true
                    tableIsMain = !mainDone && row.count == 5 && row[0] == "#"
                    if tableIsMain { mainDone = true }
                    continue
                }
                if isSeparator(row) { continue }
                if tableIsMain, row.count == 5 {
                    let title = row[1].replacingOccurrences(of: "**", with: "")
                    let done = row[3].contains("✅")
                    let priority = row[3].replacingOccurrences(of: "✅", with: "").trimmingCharacters(in: .whitespaces)
                    blocks.append(.item(Item(number: Int(row[0]), title: title, effort: row[2], priority: priority,
                                             done: done, summary: row[4])))
                } else {
                    blocks.append(.legend(row))
                }
                continue
            }
            inTable = false
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("#") {
                flush()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level <= 3, trimmed.dropFirst(level).hasPrefix(" ") {
                    blocks.append(.heading(level: level, text: String(trimmed.dropFirst(level + 1))))
                    continue
                }
            }
            if let text = bulletText(trimmed), !raw.hasPrefix(" ") {
                flush()
                blocks.append(.bullet(text))
                continue
            }
            if raw.hasPrefix(" "), paragraph.isEmpty, case .bullet(let previous)? = blocks.last {   // continuation line
                blocks[blocks.count - 1] = .bullet(previous + " " + trimmed)
                continue
            }
            paragraph.append(trimmed)
        }
        flush()
        return blocks
    }
}

/// Settings → Developer → Plans and proposals: the plans overview document, read-only, plain colours (no glass).
struct PlansView: View {
    private let blocks: [PlansDocument.Block]?

    init() {
        if let url = Bundle.main.url(forResource: "PREHLAD-PLANOV", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            blocks = PlansDocument.parse(text)
        } else {
            blocks = nil
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "P0": Color(red: 0.75, green: 0.1, blue: 0.1)
        case "P1": Color(red: 0.75, green: 0.38, blue: 0.0)
        case "P2": Color(red: 0.1, green: 0.35, blue: 0.75)
        default: Color(white: 0.4)
        }
    }

    private static let doneGreen = Color(red: 0.1, green: 0.5, blue: 0.2)

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    @ViewBuilder private func row(_ block: PlansDocument.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title.bold() : level == 2 ? .title2.bold() : .headline)
                .padding(.top, 8)
        case .paragraph(let text):
            Text(inline(text)).font(.body)
        case .bullet(let text):
            Text(inline("• " + text)).font(.body)
        case .item(let item):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: item.number.map { "\($0) · \(item.title)" } ?? item.title).font(.headline)
                HStack(spacing: 6) {
                    badge(item.priority, item.done ? Self.doneGreen : priorityColor(item.priority))
                    if item.done { badge("✓ " + L("Done"), Self.doneGreen) }
                    badge(item.effort, Color(white: 0.4))
                }
                Text(inline(item.summary)).font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        case .legend(let cells):
            (Text(inline(cells.first ?? "")).bold() + Text(verbatim: cells.count > 1 ? " — " : "")
                + Text(inline(cells.dropFirst().joined(separator: " — "))))
                .font(.subheadline)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let blocks {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in row(block) }
                } else {
                    Text(L("The plans document is not part of this build."))
                }
            }
            .padding(16)
        }
        .environment(\.openURL, OpenURLAction { _ in .discarded })   // a link must not take the user out of the app at night
        .background(Color(.systemBackground))
        .navigationTitle(L("Plans and proposals"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
