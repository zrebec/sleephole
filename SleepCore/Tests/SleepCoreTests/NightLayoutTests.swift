import Testing
@testable import SleepCore

@Suite struct NightLayoutTests {
    @Test func fitsMeansNoChange() {
        #expect(NightLayout.siteScale(natural: 700, available: 700, siteHeight: 300) == 1)
        #expect(NightLayout.siteScale(natural: 600, available: 800, siteHeight: 300) == 1)
    }

    @Test func overflowIsRemovedExactly() {
        // 60 pt too tall, a 300 pt site → shrink by 60 pt → 0.8
        let s = NightLayout.siteScale(natural: 760, available: 700, siteHeight: 300)
        #expect(abs(s - 0.8) < 1e-9)
        // the shrunk content then fits exactly
        #expect(abs((760 - 300 * (1 - s)) - 700) < 1e-9)
    }

    @Test func neverBelowTheCompactScale() {
        #expect(NightLayout.siteScale(natural: 1200, available: 700, siteHeight: 300) == 0.6)
    }

    @Test func degenerateInputs() {
        #expect(NightLayout.siteScale(natural: 800, available: 700, siteHeight: 0) == 1)
    }
}
