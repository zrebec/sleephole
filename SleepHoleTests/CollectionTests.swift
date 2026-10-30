import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Step 11b4c: the collection – the outfit and sky choices (stored, backed up, merged) and the held parcel jokers.
@MainActor @Suite(.serialized) struct CollectionTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true; Lang.current = .en }

    func date(_ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: mo, day: d, hour: h))!
    }

    func device(at now: Date) -> (model: AppModel, context: ModelContext, clock: FakeClock) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        let defaults = UserDefaults(suiteName: "sleephole-collection-\(UUID().uuidString)")!
        let model = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                             servicesEnabled: false, defaults: defaults)
        model.sync.firstReadDone = true
        return (model, c.mainContext, clock)
    }

    func win(_ d: (model: AppModel, context: ModelContext, clock: FakeClock), _ n: Int, _ prize: BoxPrize, payout: Int = 0) {
        d.model.recordBox(BoxPurchase(id: "w\(n)", at: date(10, n), nightKey: NightKey(year: 2026, month: 10, day: n),
                                      price: 400, seed: 1, tableVersion: 1, prize: prize, payout: payout))
    }

    func profile(_ d: (model: AppModel, context: ModelContext, clock: FakeClock)) -> UserProgress {
        try! d.context.fetch(FetchDescriptor<UserProgress>()).first!
    }

    // MARK: the choices

    @Test func aFirstWinIsWornAtOnceAndAChoiceKeepsTheOtherSlots() {
        let d = device(at: date(10, 20))
        #expect(d.model.buddyOutfit == .none && d.model.nightSky == nil)
        win(d, 1, .collectible(.accessory, id: "sunglasses"))
        win(d, 2, .collectible(.accessory, id: "nightcap"))
        win(d, 3, .collectible(.sky, id: "sky-02"))
        #expect(d.model.buddyOutfit == CatOutfit(head: "nightcap", face: "sunglasses"))      // never chosen: the newest per slot
        #expect(d.model.nightSkyId == "sky-02" && d.model.nightSky == .northernLights)

        win(d, 4, .collectible(.accessory, id: "top-hat"))
        d.clock.now = date(10, 21)
        d.model.chooseAccessory("nightcap", slot: .head)                                      // keeps the glasses
        #expect(d.model.buddyOutfit == CatOutfit(head: "nightcap", face: "sunglasses"))
        #expect(profile(d).outfitChoice == "nightcap,sunglasses" && profile(d).outfitChosenAt == date(10, 21))
        d.model.chooseAccessory(nil, slot: .face)
        #expect(d.model.buddyOutfit == CatOutfit(head: "nightcap"))
        d.model.chooseAccessory(nil, slot: .head)
        #expect(profile(d).outfitChoice == "" && d.model.buddyOutfit == .none)               // nothing on purpose
        win(d, 5, .collectible(.accessory, id: "rug"))
        #expect(d.model.buddyOutfit == .none)                                                 // a new win does not undo a choice

        d.model.chooseNightSky(nil)
        #expect(profile(d).nightSkyChoice == "none" && d.model.nightSky == nil)
        d.model.chooseNightSky("sky-02")
        #expect(d.model.nightSkyId == "sky-02" && profile(d).nightSkyChosenAt == date(10, 21))
    }

    @Test func aChoiceSavesAndTouchesTheSync() {
        let d = device(at: date(10, 20))
        win(d, 1, .collectible(.accessory, id: "rug"))
        let before = d.model.dataRevision
        d.model.chooseAccessory(nil, slot: .bed)
        #expect(d.model.dataRevision > before)
        let file = d.model.makeSyncFile()
        #expect(file.outfitChoice == "" && file.outfitChosenAt == date(10, 20))
    }

    // MARK: backup

    @Test func theChoicesSurviveABackup() throws {
        let a = device(at: date(10, 20))
        win(a, 1, .collectible(.accessory, id: "rug")); win(a, 2, .collectible(.sky, id: "sky-04"))
        a.model.chooseAccessory("rug", slot: .bed); a.model.chooseNightSky(nil)
        let file = try BackupFile.decode(try a.model.makeBackup().encoded())
        #expect(file.outfitChoice == "rug" && file.nightSkyChoice == "none")
        let b = device(at: date(10, 25))
        try b.model.restore(file)
        #expect(profile(b).outfitChoice == "rug" && profile(b).nightSkyChoice == "none")
        #expect(profile(b).outfitChosenAt != nil && profile(b).nightSkyChosenAt != nil)
        #expect(b.model.makeBackup().outfitChoice == "rug")
    }

    @Test func anOldBackupWithoutTheChoicesStillLoads() throws {
        let a = device(at: date(10, 20))
        a.model.chooseNightSky("sky-01")
        var object = try JSONSerialization.jsonObject(with: try a.model.makeBackup().encoded()) as! [String: Any]
        for k in ["outfitChoice", "outfitChosenAt", "nightSkyChoice", "nightSkyChosenAt"] { object.removeValue(forKey: k) }
        let old = try BackupFile.decode(try JSONSerialization.data(withJSONObject: object))
        #expect(old.outfitChoice == nil && old.nightSkyChoice == nil && old.nightSkyChosenAt == nil)
        let b = device(at: date(10, 25))
        b.model.chooseNightSky("sky-02")
        try b.model.restore(old)                                                             // the backup is the whole truth
        #expect(profile(b).nightSkyChoice == nil && profile(b).nightSkyChosenAt == nil)
    }

    // MARK: merge

    @Test func theNewerChoiceWinsAMerge() {
        let p = UserProgress()
        p.outfitChoice = "nightcap"; p.outfitChosenAt = date(10, 10)
        var file = device(at: date(10, 20)).model.makeBackup()
        // a file without a choice leaves ours
        #expect(p.merge(file) == false || p.outfitChoice == "nightcap")
        #expect(p.outfitChoice == "nightcap" && p.nightSkyChoice == nil)
        // an older choice leaves ours
        file.outfitChoice = "top-hat"; file.outfitChosenAt = date(10, 9)
        _ = p.merge(file)
        #expect(p.outfitChoice == "nightcap")
        // a newer one wins, with its stamp; a never-chosen device adopts a stamped choice
        file.outfitChoice = ""; file.outfitChosenAt = date(10, 11)
        file.nightSkyChoice = "sky-03"; file.nightSkyChosenAt = date(10, 11)
        #expect(p.merge(file))
        #expect(p.outfitChoice == "" && p.outfitChosenAt == date(10, 11))
        #expect(p.nightSkyChoice == "sky-03" && p.nightSkyChosenAt == date(10, 11))
        #expect(p.merge(file) == false)                                                      // idempotent
    }

    // MARK: held parcel jokers

    @Test func aHeldParcelJokerIsListedAndUsedForFree() {
        let d = device(at: date(10, 20))
        win(d, 5, .joker(.silver))
        win(d, 6, .joker(.bronze), payout: 100)                                              // converted: nobody holds it
        let coinsBefore = d.model.coins
        #expect(d.model.heldBoxJokers().map(\.id) == ["w5"])
        #expect(d.model.jokerBlock(.silver, fromBox: "w5") == nil)
        d.model.useJoker(.silver, fromBox: "w5")
        #expect(d.model.heldBoxJokers().isEmpty)
        #expect(d.model.jokerState.uses.contains { $0.boxId == "w5" && $0.tier == .silver })
        #expect(d.model.coins == coinsBefore)                                                // no coins, the month's own slot is free
        #expect(d.model.jokerBlock(.silver) != .alreadyUsedThisMonth)                        // the month's own slot is untouched
    }
}
