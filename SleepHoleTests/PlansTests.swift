#if DEBUG
import Foundation
import Testing
@testable import SleepHole

/// The plans overview parser (Settings → Developer → Plans and proposals).
struct PlansTests {
    @Test func parsesASmallSample() {
        let md = """
        # Title

        First line of a paragraph
        second line of it.

        ## Section

        * one
          continued here
        - two
        1. numbered

        | Mark | Meaning |
        |---|---|
        | XS | tiny |

        | # | What | Effort | Priority | Description |
        |---|---|---|---|---|
        | 1 | **Alpha** | S | P0 ✅ | does a |
        | – | Beta | M | P3 | does b |
        """
        let blocks = PlansDocument.parse(md)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line of a paragraph second line of it."),
            .heading(level: 2, text: "Section"),
            .bullet("one continued here"),
            .bullet("two"),
            .bullet("1. numbered"),
            .legend(["XS", "tiny"]),
            .item(.init(number: 1, title: "Alpha", effort: "S", priority: "P0", done: true, summary: "does a")),
            .item(.init(number: nil, title: "Beta", effort: "M", priority: "P3", done: false, summary: "does b")),
        ])
    }

    @Test(arguments: ["PREHLAD-PLANOV", "PREHLAD-PLANOV.cs"]) func parsesTheRealDocument(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "md"))
        let blocks = PlansDocument.parse(try String(contentsOf: url, encoding: .utf8))
        let items: [PlansDocument.Item] = blocks.compactMap { if case .item(let i) = $0 { i } else { nil } }
        #expect(items.count >= 20)
        for i in items {
            #expect(!i.title.isEmpty && !i.effort.isEmpty && !i.priority.isEmpty && !i.summary.isEmpty)
        }
        #expect(items.allSatisfy { !$0.priority.contains("✅") })
        let numbers = items.compactMap(\.number)
        #expect(numbers == Array(1...numbers.count))
        #expect(blocks.contains { if case .heading = $0 { true } else { false } })
        #expect(blocks.contains { if case .paragraph = $0 { true } else { false } })
    }

    private static func marker(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { return String(t.prefix { $0 == "#" }) }
        if t.hasPrefix("- ") || t.hasPrefix("* ") { return "-" }
        if let dot = t.firstIndex(of: "."), dot != t.startIndex, t[..<dot].allSatisfy(\.isNumber),
           t[t.index(after: dot)...].hasPrefix(" ") { return "N." }
        return ""
    }

    /// Effort cells contain words, so only the size letters and numbers are compared, in order.
    private static func sizeTokens(_ s: String) -> [String] {
        s.matches(of: /\b(?:XS|S|M|L)\b|\d+/).map { String($0.output) }
    }

    private static func kind(_ b: PlansDocument.Block) -> String {
        switch b {
        case .heading(let l, _): "heading\(l)"
        case .paragraph: "paragraph"
        case .bullet: "bullet"
        case .item: "item"
        case .legend: "legend"
        }
    }

    @Test func czechCopyMatchesTheSlovakDocument() throws {
        let sk = try String(contentsOf: try #require(Bundle.main.url(forResource: "PREHLAD-PLANOV", withExtension: "md")), encoding: .utf8)
        let cs = try String(contentsOf: try #require(Bundle.main.url(forResource: "PREHLAD-PLANOV.cs", withExtension: "md")), encoding: .utf8)
        let a = sk.components(separatedBy: "\n"), b = cs.components(separatedBy: "\n")
        #expect(a.count == b.count, "line count: sk \(a.count), cs \(b.count)")
        for (n, pair) in zip(a, b).enumerated() {
            let (x, y) = pair
            #expect(Self.marker(x) == Self.marker(y), "line \(n + 1): markdown marker differs: «\(y)»")
            #expect(x.filter { $0 == "|" }.count == y.filter { $0 == "|" }.count, "line \(n + 1): number of '|' differs: «\(y)»")
        }
        let ba = PlansDocument.parse(sk), bb = PlansDocument.parse(cs)
        #expect(ba.map(Self.kind) == bb.map(Self.kind), "the sequence of block kinds differs")
        let ia: [PlansDocument.Item] = ba.compactMap { if case .item(let i) = $0 { i } else { nil } }
        let ib: [PlansDocument.Item] = bb.compactMap { if case .item(let i) = $0 { i } else { nil } }
        #expect(ia.count == ib.count, "item count: sk \(ia.count), cs \(ib.count)")
        for (x, y) in zip(ia, ib) {
            let id = "item #\(x.number.map(String.init) ?? "–") (\(y.title))"
            #expect(x.number == y.number, "\(id): number differs (sk \(x.number.map(String.init) ?? "–"))")
            #expect(Self.sizeTokens(x.effort) == Self.sizeTokens(y.effort), "\(id): effort differs (sk \(x.effort), cs \(y.effort))")
            #expect(x.done == y.done, "\(id): done (✅) differs")
            #expect(x.priority.contains("✅") == y.priority.contains("✅"), "\(id): ✅ in priority differs")
        }
    }

    @Test func documentURLFollowsTheLanguage() throws {
        #expect(try #require(PlansView.documentURL(for: .cs)).lastPathComponent == "PREHLAD-PLANOV.cs.md")
        #expect(try #require(PlansView.documentURL(for: .sk)).lastPathComponent == "PREHLAD-PLANOV.md")
        #expect(try #require(PlansView.documentURL(for: .en)).lastPathComponent == "PREHLAD-PLANOV.md")
    }
}
#endif
