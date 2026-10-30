import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Step 11b4c2: the list of parcels bought – order and sums.
struct BoughtParcelsTests {
    let cal = Calendar.current

    func box(_ n: Int, price: Int = 400, prize: BoxPrize, payout: Int = 0) -> BoxPurchase {
        BoxPurchase(id: "b\(n)", at: cal.date(from: DateComponents(year: 2026, month: 10, day: n, hour: 8))!,
                    nightKey: NightKey(year: 2026, month: 10, day: n), price: price, seed: 1, tableVersion: 1,
                    prize: prize, payout: payout)
    }

    @Test func newestFirstAndTheSums() {
        let list = BoughtParcels([box(3, price: 400, prize: .coins, payout: 250),
                                  box(9, price: 700, prize: .luckyNight),
                                  box(5, price: 400, prize: .collectible(.sky, id: "sky-02"), payout: 100)])
        #expect(list.newestFirst.map(\.id) == ["b9", "b5", "b3"])
        #expect(list.spent == 1500 && list.back == 350)
    }

    @Test func emptyIsZero() {
        let list = BoughtParcels([])
        #expect(list.newestFirst.isEmpty && list.spent == 0 && list.back == 0)
    }

    @MainActor @Test func anUnknownPrizeKeepsItsRow() {
        Lang.current = .en
        let unknown = box(4, prize: .unknown("future"))
        let list = BoughtParcels([box(2, prize: .luckyNight), unknown])
        #expect(list.newestFirst.count == 2 && list.newestFirst.first?.id == "b4")
        #expect(!BoxPrizeText.make(for: unknown, catalog: nil).title.isEmpty)
    }
}
