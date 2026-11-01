import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Build 11, step 11b4a: the box shop's offer, the purchase and the words of a prize.
@MainActor @Suite(.serialized) struct BoxShopTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true; Lang.current = .en }

    func date(_ mo: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: mo, day: d, hour: h, minute: min))!
    }

    func device(at now: Date) -> (model: AppModel, context: ModelContext, clock: FakeClock) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        let defaults = UserDefaults(suiteName: "sleephole-shop-\(UUID().uuidString)")!
        let model = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                             servicesEnabled: false, defaults: defaults)
        model.sync.firstReadDone = true
        return (model, c.mainContext, clock)
    }

    /// A real night that starts on the evening before `morning` and is confirmed on time (complete) or `late` minutes
    /// after the wake time (unfinished). Leaves the clock at the confirmation.
    func night(_ d: (model: AppModel, context: ModelContext, clock: FakeClock), morning: Int, month: Int = 10,
               late: Int = 1) {
        d.clock.now = date(month, morning - 1, 22, 25); d.model.refresh(); d.model.startNight()
        d.clock.now = date(month, morning, 6, 30 + late); d.model.refresh(); d.model.confirm(code: "1234")
        d.model.acknowledgeResult()
    }

    /// Complete nights on the mornings `from…to` of October, the clock at noon of `to`.
    func richDevice(from: Int = 20, to: Int = 24) -> (model: AppModel, context: ModelContext, clock: FakeClock) {
        let d = device(at: date(10, from - 1))
        for m in from...to { night(d, morning: m) }
        d.clock.now = date(10, to, 12); d.model.refresh()
        return d
    }

    // MARK: the offer

    @Test func noNightTodayNeedsACompleteNight() {
        let d = device(at: date(10, 21))
        #expect(d.model.boxOffer() == .needsCompleteNight)
        #expect(d.model.buyBox() == nil)
        #expect(d.model.boxes().isEmpty)
    }

    @Test func anUnfinishedNightOpensNoBox() {
        let d = device(at: date(10, 21))
        night(d, morning: 22, late: 30)                                    // confirmed 30 min late → unfinished
        d.clock.now = date(10, 22, 12); d.model.refresh()
        #expect(d.model.coreResults().last?.outcome == .unfinished)
        #expect(d.model.boxOffer() == .needsCompleteNight)
    }

    @Test func anExcusedNightOpensNoBox() {
        let d = device(at: date(10, 19))
        night(d, morning: 20); night(d, morning: 21)                       // a streak, then a missed night 22 → 23
        d.clock.now = date(10, 23, 12); d.model.refresh()                  // the bronze joker covers the missed morning of 22
        let key = NightKey("2026-10-22")!
        d.clock.now = date(10, 22, 12); d.model.refresh()
        #expect(d.model.boxDay == key)
        // night 22 was never slept → no complete night today; move to the day after the miss, which the joker covers
        d.clock.now = date(10, 23, 12); d.model.refresh()
        let excused = d.model.coreResults().first { $0.outcome == .excused }
        #expect(excused != nil)
        #expect(d.model.boxOffer() == .needsCompleteNight)
        #expect(d.model.coreResults().last { $0.key == d.model.boxDay }?.outcome != .complete)
    }

    @Test func anUncountedTestNightAndANapOpenNoBox() {
        let d = device(at: date(10, 21, 15))
        d.model.startTestNight(minutes: 15, grace: 300); d.model.startNight()
        d.clock.now += 15 * 60; d.model.refresh()
        #expect(d.model.confirm()); d.model.acknowledgeResult()
        #expect(d.model.boxOffer() == .needsCompleteNight)
        let n = device(at: date(10, 21, 13, 30))
        n.model.startNap(); n.clock.now = date(10, 21, 14, 0); n.model.refresh()
        #expect(n.model.confirm()); n.model.acknowledgeResult()
        #expect(n.model.boxOffer() == .needsCompleteNight)
    }

    @Test func aCompleteNightWithEnoughCoinsMakesTheBoxAvailable() {
        let d = richDevice()
        #expect(d.model.coins >= 400)
        guard case .available(let price, let n) = d.model.boxOffer() else { Issue.record("not available: \(d.model.boxOffer())"); return }
        #expect(n == 1)
        #expect(price == BoxRules.price(balance: d.model.coins, boxNumber: 1))
    }

    @Test func notEnoughCoinsShowsWhatIsMissing() {
        let d = device(at: date(10, 21))
        night(d, morning: 22)
        d.clock.now = date(10, 22, 12); d.model.refresh()
        let coins = d.model.coins
        #expect(coins > 0 && coins < 400)
        #expect(d.model.boxOffer() == .notEnoughCoins(price: 400, missing: 400 - coins, boxNumber: 1))
        #expect(d.model.buyBox() == nil)
        #expect(d.model.boxes().isEmpty)
    }

    // MARK: the purchase

    @Test func buyingWritesOneRecordWithTheDrawOfTheSeed() throws {
        let d = richDevice()
        let balance = d.model.coins
        guard case .available(let price, _) = d.model.boxOffer() else { Issue.record("not available"); return }
        let seed: UInt64 = 2                                               // half the price back
        let box = try #require(d.model.buyBox(seed: seed))
        let records = d.model.boxRecords()
        #expect(records.count == 1)
        #expect(box.nightKey == d.model.boxDay && box.nightKey == NightKey("2026-10-24")!)
        #expect(box.price == price && box.seed == seed && box.tableVersion == 1)
        let draw = BoxRules.draw(seed: seed, price: price, nightKey: box.nightKey, boxes: [], uses: [], calendar: cal)
        #expect(box.prize == draw.prize && box.payout == draw.payout && box.payout == price / 2)
        #expect(records[0].purchase == box)
        #expect(d.model.coins == balance + box.payout - price)
        #expect(d.model.todaysBox() == box)
    }

    @Test func aSecondBoxTheSameDayIsRefused() {
        let d = richDevice()
        #expect(d.model.buyBox(seed: 5) != nil)
        #expect(d.model.boxOffer() == .alreadyBoughtToday)
        let coins = d.model.coins
        #expect(d.model.buyBox(seed: 5) == nil)
        #expect(d.model.boxRecords().count == 1 && d.model.coins == coins)
    }

    @Test func theRandomSeedDrawsAndIsStoredWithTheBox() throws {
        let d = richDevice()
        let box = try #require(d.model.buyBox())
        #expect(d.model.boxes() == [box] && !box.id.isEmpty)
    }

    @Test func theFirstBoxNeedsNoReserveButTheSecondDoes() throws {
        // balance 600 exactly: price 400, 200 stay – fine for the very first box, never for a later one
        #expect(BoxRules.canAfford(balance: 600, price: 400, firstEver: true))
        #expect(!BoxRules.canAfford(balance: 600, price: 400, firstEver: false))
        let d = richDevice(from: 18, to: 24)                               // seven nights → plenty of coins
        let first = try #require(d.model.buyBox(seed: 12))
        #expect(first.price >= 400)
        d.clock.now = date(10, 25, 12); d.model.refresh()
        night(d, morning: 25)
        d.clock.now = date(10, 25, 12); d.model.refresh()
        switch d.model.boxOffer() {
        case .available(let price, let n):
            #expect(n == 2 && d.model.coins - price >= BoxRules.reserve)
        case .notEnoughCoins(let price, let missing, let n):
            #expect(n == 2 && missing > 0 && !BoxRules.canAfford(balance: d.model.coins, price: price, firstEver: false))
        default: Issue.record("unexpected \(d.model.boxOffer())")
        }
    }

    @Test func nineBoxesFillTheMonth() {
        let d = richDevice()
        let key = d.model.boxDay
        for i in 0..<9 {
            d.model.recordBox(BoxPurchase(id: "m\(i)", at: date(10, 1 + i), nightKey: key.adding(days: -1 - i, calendar: cal),
                                          price: 400, seed: 1, tableVersion: 1, prize: .coins, payout: 400))
        }
        #expect(d.model.boxOffer() == .monthFull)
        #expect(d.model.buyBox() == nil)
    }

    // MARK: Fmt.permille

    @Test func permilleReadsInBothLanguages() {
        Lang.current = .en
        #expect(Fmt.permille(250) == "25%")
        #expect(Fmt.permille(8) == "0.8%")
        #expect(Fmt.permille(2) == "0.2%")
        Lang.current = .sk
        defer { Lang.current = .en }
        #expect(Fmt.permille(250).replacingOccurrences(of: "\u{a0}", with: " ") == "25 %")
        #expect(Fmt.permille(8).replacingOccurrences(of: "\u{a0}", with: " ") == "0,8 %")
    }

    @Test func theOddsRowsAllHaveWords() {
        for lang in AppLanguage.allCases {
            Lang.current = lang
            for row in BoxRules.odds {
                let (emoji, name, _) = BoxShopView.describe(row.roll)
                #expect(!emoji.isEmpty && !name.isEmpty)
            }
        }
        Lang.current = .en
        #expect(BoxShopView.describe(.coins(tenths: 30)).name == "Three times the price")
        #expect(BoxShopView.describe(.coins(tenths: 25)).name == "2.5× the price")
    }

    // MARK: the words of a prize

    func box(_ prize: BoxPrize, payout: Int = 0, price: Int = 400) -> BoxPurchase {
        BoxPurchase(id: "x", at: date(10, 20), nightKey: NightKey("2026-10-20")!, price: price, seed: 1, tableVersion: 1,
                    prize: prize, payout: payout)
    }

    @Test func prizeTextsForEveryKindInBothLanguages() {
        for lang in AppLanguage.allCases {
            Lang.current = lang
            let cat = sprites.catalog
            let coins = BoxPrizeText.make(for: box(.coins, payout: 800), catalog: cat)
            #expect(coins.title.contains("800"))
            let big = BoxPrizeText.make(for: box(.coins, payout: 1530), catalog: cat)
            #expect(big.title.contains("530") && !big.title.contains("1530"))   // digits are grouped in either language
            let lucky = BoxPrizeText.make(for: box(.luckyNight), catalog: cat)
            #expect(!lucky.title.isEmpty && lucky.detail?.isEmpty == false)
            let fresh = BoxPrizeText.make(for: box(.collectible(.postcard, id: "postcard-03")), catalog: cat)
            #expect(fresh.postcardId == "postcard-03" && !fresh.title.isEmpty && fresh.detail?.isEmpty == false)
            let dupe = BoxPrizeText.make(for: box(.collectible(.sky, id: "sky-02"), payout: 100), catalog: cat)
            #expect(dupe.detail?.contains("100") == true && dupe.title == CollectibleText.skyName("sky-02"))
            let deco = BoxPrizeText.make(for: box(.collectible(.decoration, id: "decoration-01")), catalog: cat)
            #expect(!deco.title.isEmpty && deco.postcardId == nil)
            let cap = BoxPrizeText.make(for: box(.collectible(.accessory, id: "rug")), catalog: cat)
            #expect(cap.title == CollectibleText.accessoryName("rug"))
            let kept = BoxPrizeText.make(for: box(.joker(.bronze)), catalog: cat, calendar: cal)
            #expect(kept.title == JokerTier.bronze.title && kept.detail?.contains("2026") == true)
            let converted = BoxPrizeText.make(for: box(.joker(.silver), payout: 100), catalog: cat)
            #expect(converted.detail?.contains("100") == true)
            let unknown = BoxPrizeText.make(for: box(.unknown("item:newkind:z")), catalog: cat)
            #expect(!unknown.title.isEmpty && unknown.detail == nil)
        }
        Lang.current = .en
    }
}
