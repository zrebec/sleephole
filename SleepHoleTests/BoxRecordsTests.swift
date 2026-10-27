import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Build 11, step 11b2: the mystery-box records – SwiftData rows, the JSON backup, the sync union and the balance.
@MainActor @Suite struct BoxRecordsTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: mo, day: d, hour: h))!
    }

    func device(at now: Date) -> (model: AppModel, context: ModelContext, clock: FakeClock) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        let defaults = UserDefaults(suiteName: "sleephole-box-\(UUID().uuidString)")!
        let model = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                             servicesEnabled: false, defaults: defaults)
        model.sync.firstReadDone = true
        return (model, c.mainContext, clock)
    }

    func purchase(_ id: String, night: String = "2026-10-20", price: Int = 400, payout: Int = 0,
                  prize: BoxPrize = .coins, seed: UInt64 = UInt64.max - 3, frac: Double = 0.5) -> BoxPurchase {
        BoxPurchase(id: id, at: date(10, 20) + frac, nightKey: NightKey(night)!, price: price, seed: seed, tableVersion: 1,
                    prize: prize, payout: payout)
    }

    @Test func aRecordKeepsEveryFieldEvenAHugeSeed() {
        let p = purchase("b1", prize: .collectible(.postcard, id: "tip-03"), seed: UInt64.max)
        let r = BoxRecord(p)
        #expect(r.purchase == p)
        #expect(BoxRecord(purchase("b2", seed: 1 << 63)).purchase?.seed == 1 << 63)
        r.prizeRaw = "garbage"
        #expect(r.purchase?.prize == .unknown("garbage"))                  // an unreadable prize is kept, never a crash
        r.nightKey = "garbage"
        #expect(r.purchase == nil)                                         // only a corrupt night key drops the row
    }

    @Test func theBalanceIncludesTheBoxes() throws {
        let d = device(at: date(10, 21))
        let before = d.model.coins
        #expect(before == 0)                                               // an empty town
        d.context.insert(BoxRecord(purchase("b1", price: 400, payout: 0)))
        d.context.insert(BoxRecord(purchase("b2", night: "2026-10-21", price: 500, payout: 1000, prize: .coins)))
        try d.context.save()
        d.model.refresh()
        #expect(d.model.boxes().count == 2)
        #expect(Boxes.coinDelta(d.model.boxes()) == 100)
        #expect(d.model.coins == 100)                                      // 1 000 paid out − 900 in prices
        d.context.insert(BoxRecord(purchase("b3", night: "2026-10-22", price: 5000, payout: 0)))
        try d.context.save()
        d.model.refresh()
        #expect(d.model.coins == 0)                                        // never negative
    }

    @Test func aBackupRoundTripKeepsBoxesAndAJokersBoxId() throws {
        let a = device(at: date(11, 2))
        a.context.insert(BoxRecord(purchase("b1", night: "2026-10-31", prize: .joker(.bronze), frac: 0)))       // a backup keeps whole seconds
        a.context.insert(BoxRecord(purchase("b2", prize: .collectible(.sky, id: "aurora"), seed: UInt64.max, frac: 0)))
        a.context.insert(JokerRecord(at: date(11, 2), tier: .bronze, firstNight: NightKey("2026-11-02")!, boxId: "b1"))
        a.context.insert(JokerRecord(at: date(11, 2) + 1, tier: .silver, firstNight: NightKey("2026-11-03")!))
        try a.context.save()
        let file = a.model.makeBackup()
        #expect(file.boxes?.count == 2 && file.boxes?.first { $0.id == "b2" }?.seed == String(UInt64.max))
        let data = try file.encoded()
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"boxes\"") && json.contains("\"boxId\""))
        let b = device(at: date(11, 3))
        try b.model.restore(try BackupFile.decode(data))
        #expect(b.model.boxes() == a.model.boxes())
        #expect(b.model.jokerRecords().map(\.boxId) == ["b1", nil])
        #expect(b.model.makeBackup().boxes == file.boxes && b.model.makeBackup().jokers == file.jokers)
        // the backup is the whole truth: restoring one without boxes clears them
        var old = file; old.boxes = nil
        try b.model.restore(old)
        #expect(b.model.boxes().isEmpty)
    }

    @Test func anOldBackupWithoutBoxesStillImports() throws {
        let a = device(at: date(10, 21))
        var file = a.model.makeBackup()
        file.boxes = nil
        file.jokers = [.init(at: date(10, 5), tier: "bronze", firstNight: "2026-10-05")]
        // the JSON of an old file has neither key at all
        var object = try JSONSerialization.jsonObject(with: try file.encoded()) as! [String: Any]
        #expect(object["boxes"] == nil)
        object["jokers"] = [["at": "2026-10-05T10:00:00Z", "tier": "bronze", "firstNight": "2026-10-05"]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try BackupFile.decode(data)
        #expect(decoded.boxes == nil && decoded.jokers?.first?.boxId == nil)
        let b = device(at: date(10, 21))
        try b.model.restore(decoded)
        #expect(b.model.boxes().isEmpty && b.model.jokerRecords().count == 1 && b.model.jokerRecords()[0].boxId == nil)
    }

    @Test func syncMergesBoxesByIdWithoutDuplicatesOrDeletes() throws {
        let a = device(at: date(10, 21)), b = device(at: date(10, 21))
        a.context.insert(BoxRecord(purchase("b1")))
        a.context.insert(BoxRecord(purchase("b2", night: "2026-10-21")))
        b.context.insert(BoxRecord(purchase("b2", night: "2026-10-21")))         // the same box on both
        b.context.insert(BoxRecord(purchase("b3", night: "2026-10-22")))
        try a.context.save(); try b.context.save()
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]))
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)         // idempotent
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)
        for d in [a, b] { #expect(Set(d.model.boxes().map(\.id)) == ["b1", "b2", "b3"] && d.model.boxes().count == 3) }
        // a file with fewer boxes never deletes; a changed copy with a known id is skipped, not replaced
        var thin = a.model.makeSyncFile()
        thin.boxes = [thin.boxes![0]]
        thin.boxes![0].payout = 999
        #expect(try a.model.mergeSync([thin]) == false)
        #expect(a.model.boxes().count == 3 && !a.model.boxes().contains { $0.payout == 999 })
        // an unreadable entry is skipped
        var bad = a.model.makeSyncFile()
        bad.boxes = [.init(id: "x", at: date(10, 22), nightKey: "2026-10-22", price: 400, seed: "nope", tableVersion: 1,
                           prize: "coins", payout: 0)]
        #expect(try a.model.mergeSync([bad]) == false)
    }

    @Test func syncJokerCopiesDifferingOnlyByBoxIdAreOne() throws {
        let a = device(at: date(11, 5)), b = device(at: date(11, 5))
        let first = NightKey("2026-11-02")!
        a.context.insert(JokerRecord(at: date(11, 2) + 0.25, tier: .bronze, firstNight: first))                  // no box id yet
        b.context.insert(JokerRecord(at: date(11, 2) + 0.25, tier: .bronze, firstNight: first, boxId: "b1"))
        try a.context.save(); try b.context.save()
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]))                  // a learns the box id
        #expect(a.model.jokerRecords().count == 1 && a.model.jokerRecords()[0].boxId == "b1")
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)
        #expect(b.model.jokerRecords().count == 1)
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)
        // a local box id is never overwritten by another one
        var other = b.model.makeSyncFile()
        other.jokers = [.init(at: date(11, 2) + 0.25, tier: "bronze", firstNight: "2026-11-02", boxId: "other")]
        #expect(try a.model.mergeSync([other]) == false)
        #expect(a.model.jokerRecords()[0].boxId == "b1")
    }

    @Test func aBoxBronzeSavesASecondMissedNightInTheApp() throws {
        let d = device(at: date(11, 20))
        d.context.insert(BoxRecord(purchase("bb", night: "2026-10-31", prize: .joker(.bronze))))
        try d.context.save()
        d.model.refresh()
        #expect(d.model.jokerBlock(.bronze, fromBox: "bb") == nil)
        #expect(d.model.jokerBlock(.bronze, fromBox: "nope") == .notHeldFromBox)
        let before = d.model.coins
        d.model.useJoker(.bronze, fromBox: "bb")
        #expect(d.model.coins == before)                                   // a box joker costs nothing
        #expect(d.model.jokerRecords().map(\.boxId) == ["bb"])
        #expect(d.model.jokerBlock(.bronze, fromBox: "bb") == .notHeldFromBox)     // used up
        #expect(d.model.jokerBlock(.bronze) == nil)                                // the month's own bronze is untouched
    }

    @Test func aBoxWithAnUnknownPrizeStillCountsAndTravelsUnchanged() throws {
        let a = device(at: date(10, 21)), b = device(at: date(10, 21))
        let raw = "item:frame:x1"                                         // a kind this build does not know
        a.context.insert(BoxRecord(id: "u1", at: date(10, 21), nightKey: NightKey("2026-10-21")!, price: 500,
                                   seed: UInt64.max, tableVersion: 2, prize: .unknown(raw), payout: 100))
        try a.context.save()
        a.model.refresh()
        let boxes = a.model.boxes()
        #expect(boxes.count == 1 && boxes[0].prize == .unknown(raw))
        #expect(Boxes.coinDelta(boxes) == -400)
        #expect(Boxes.count(inMonthOf: NightKey("2026-10-01")!, boxes: boxes) == 1)
        #expect(Boxes.bought(on: NightKey("2026-10-21")!, boxes: boxes))
        #expect(CollectibleKind.allCases.allSatisfy { Boxes.owned($0, boxes: boxes).isEmpty })
        #expect(Boxes.heldJokers(boxes: boxes, uses: [], at: NightKey("2026-10-25")!, calendar: cal).isEmpty)
        // a sync merge and a backup round trip keep the prize string byte-identical
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))
        #expect(b.model.boxRecords().map(\.prizeRaw) == [raw] && b.model.boxRecords()[0].seed == UInt64.max)
        #expect(b.model.coins == 0 && Boxes.coinDelta(b.model.boxes()) == -400)
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)
        let c = device(at: date(10, 22))
        try c.model.restore(try BackupFile.decode(try a.model.makeBackup().encoded()))
        #expect(c.model.boxRecords().map(\.prizeRaw) == [raw])
        #expect(c.model.makeBackup().boxes?.map(\.prize) == [raw])
    }
}
