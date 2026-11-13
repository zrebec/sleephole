import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// The date line on the result screen (13ai).
@MainActor
struct ResultDateTests {
    private func with(_ lang: AppLanguage, _ body: () -> Void) {
        let old = Lang.current
        defer { Lang.current = old }
        Lang.current = lang
        body()
    }

    private func night(_ y: Int, _ m: Int, _ d: Int, nap: Bool = false) -> String {
        Fmt.resultDate(NightKey(year: y, month: m, day: d), nap: nap)
    }

    @Test func allSevenWeekdaysSlovak() {
        with(.sk) {
            #expect(night(2026, 11, 9) == "Noc z nedele 8. 11. na pondelok 9. 11. 2026")
            #expect(night(2026, 11, 10) == "Noc z pondelka 9. 11. na utorok 10. 11. 2026")
            #expect(night(2026, 11, 11) == "Noc z utorka 10. 11. na stredu 11. 11. 2026")
            #expect(night(2026, 11, 12) == "Noc zo stredy 11. 11. na štvrtok 12. 11. 2026")
            #expect(night(2026, 11, 13) == "Noc zo štvrtka 12. 11. na piatok 13. 11. 2026")
            #expect(night(2026, 11, 14) == "Noc z piatka 13. 11. na sobotu 14. 11. 2026")
            #expect(night(2026, 11, 15) == "Noc zo soboty 14. 11. na nedeľu 15. 11. 2026")
        }
    }

    @Test func otherLanguages() {
        with(.cs) { #expect(night(2026, 11, 12) == "Noc ze středy 11. 11. na čtvrtek 12. 11. 2026") }
        with(.en) { #expect(night(2026, 11, 12) == "Night from Wednesday Nov 11 to Thursday Nov 12, 2026") }
    }

    @Test func yearBoundary() {
        with(.sk) { #expect(night(2027, 1, 1) == "Noc zo štvrtka 31. 12. na piatok 1. 1. 2027") }
    }

    @Test func nap() {
        with(.sk) { #expect(night(2026, 11, 12, nap: true) == "Štvrtok 12. 11. 2026") }
        with(.cs) { #expect(night(2026, 11, 12, nap: true) == "Čtvrtek 12. 11. 2026") }
        with(.en) { #expect(night(2026, 11, 12, nap: true) == "Thursday Nov 12, 2026") }
    }
}
