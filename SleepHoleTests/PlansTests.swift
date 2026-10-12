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

    @Test func parsesTheRealDocument() throws {
        let url = try #require(Bundle.main.url(forResource: "PREHLAD-PLANOV", withExtension: "md"))
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
}
#endif
