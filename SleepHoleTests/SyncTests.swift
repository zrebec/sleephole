import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Phase SYNC, step S1: the sync file and the merge of other devices' files. Two models with two in-memory stores
/// stand for two devices – no iCloud anywhere.
@MainActor
struct SyncTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    /// One device: its own store, model and clock.
    @MainActor struct Device {
        let container: ModelContainer
        let model: AppModel
        let clock: FakeClock
        var context: ModelContext { container.mainContext }
    }

    func device(at now: Date) -> Device {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        // its own UserDefaults: nothing leaks between the devices, and the first read of the sync place counts as finished
        // (a device that has not made it yet stamps no settings – `SyncEngineTests` covers that)
        let defaults = UserDefaults(suiteName: "sleephole-sync-\(UUID().uuidString)")!
        let model = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                             servicesEnabled: false, defaults: defaults)
        model.sync.firstReadDone = true
        return Device(container: c, model: model, clock: clock)
    }

    /// A whole night started at 22:25 on `day` and confirmed a minute after the wake time (a complete night).
    func night(_ d: Device, day: Int) {
        d.clock.now = date(day, 22, 25); d.model.refresh(); d.model.startNight()
        d.clock.now = date(day + 1, 6, 30) + 60; d.model.refresh()
        d.model.confirm(code: "1234")
        d.model.acknowledgeResult()
    }

    /// The record of the night that STARTED on `day` (its key is the morning after).
    func record(_ d: Device, day: Int) -> NightRecord {
        d.model.records().first { $0.keyString == String(format: "2026-10-%02d", day + 1) }!
    }

    func nights(_ d: Device) -> [BackupFile.Night] { d.model.makeSyncFile().nights }

    func profile(_ d: Device) -> UserProgress { try! d.context.fetch(FetchDescriptor<UserProgress>()).first! }

    func now(_ devices: Device..., at t: Date) {
        for d in devices { d.clock.now = t; d.model.refresh() }
    }

    func hasSleepValues(_ n: BackupFile.Night) -> Bool {
        n.fellAsleepAt != nil || n.sleepEndedAt != nil || n.asleepSeconds != nil || n.awakeSeconds != nil
            || n.sleepSourceName != nil || n.sleepReadAt != nil || n.sleepSourcesData != nil || n.sleepRuleVersion != nil
    }

    /// A building that is not `id`.
    func otherBuilding(than id: String) -> String { ["l1-bigblock-e", "l1-bigblock-i"].first { $0 != id }! }

    // MARK: 1 – a night travels

    @Test func aNightBuiltOnOneDeviceAppearsOnTheOther() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        for day in 1...3 { night(a, day: day) }
        now(b, at: a.clock.now)
        let file = a.model.makeSyncFile()

        #expect(try b.model.mergeSync([file]))
        #expect(b.model.records().count == 3)
        #expect(b.model.townSnapshot?.buildings.map(\.buildingId) == a.model.townSnapshot?.buildings.map(\.buildingId))
        #expect(b.model.builtNights == 3 && b.model.coins == a.model.coins && b.model.coins > 0)
        #expect(b.model.streak == a.model.streak && b.model.streak == 3)
        #expect(nights(b) == nights(a))

        // the same file again changes nothing
        let before = b.model.makeSyncFile()
        #expect(try b.model.mergeSync([file]) == false)
        #expect(b.model.makeSyncFile() == before)
    }

    // MARK: 2, 3 – two copies of one night

    @Test func twoDifferentCopiesOfOneNightEndAsTheSameCopyOnBothDevices() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        night(a, day: 1); night(b, day: 1)
        let rb = record(b, day: 1)
        rb.outcomeRaw = Outcome.ruins.rawValue                           // B's copy of the night went wrong
        rb.buildingId = otherBuilding(than: record(a, day: 1).buildingId)
        try b.context.save()

        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)  // A keeps its better copy
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))            // B takes it
        #expect(nights(a) == nights(b))
        #expect(nights(a).count == 1 && nights(a)[0].outcomeRaw == Outcome.complete.rawValue)
        #expect(b.model.records().count == 1 && b.model.builtNights == 1)
    }

    @Test(arguments: [true, false]) func withTheSameRankTheCopyThatStartedEarlierWinsOnBoth(aStartsEarlier: Bool) throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        night(a, day: 1); night(b, day: 1)
        let ra = record(a, day: 1), rb = record(b, day: 1)
        rb.startedAt = ra.startedAt! + (aStartsEarlier ? 30 : -30)
        rb.buildingId = otherBuilding(than: ra.buildingId)
        let expected = aStartsEarlier ? ra.buildingId : rb.buildingId
        try b.context.save()

        try a.model.mergeSync([b.model.makeSyncFile()])
        try b.model.mergeSync([a.model.makeSyncFile()])
        #expect(nights(a) == nights(b))
        #expect(nights(a)[0].buildingId == expected)
        #expect(nights(a)[0].startedAt == min(ra.startedAt!, rb.startedAt!))
    }

    // MARK: 4 – sleep values stay on the device

    @Test func sleepValuesNeverTravelAndAMergeKeepsTheLocalOnes() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12)), c = device(at: date(1, 12))
        night(a, day: 1); night(b, day: 1)
        let ra = record(a, day: 1), rb = record(b, day: 1)
        ra.fellAsleepAt = date(1, 23, 0); ra.sleepEndedAt = date(2, 6, 0); ra.asleepSeconds = 25_000
        ra.awakeSeconds = 900; ra.sleepSourceName = "Source A"; ra.sleepReadAt = date(2, 7, 0)
        ra.sleepSourcesData = Data([1, 2, 3]); ra.sleepRuleVersion = 3
        #expect(a.model.makeBackup().nights.allSatisfy(hasSleepValues))             // the backup keeps them …
        let file = a.model.makeSyncFile()
        #expect(file.nights.count == 1 && !file.nights.contains(where: hasSleepValues))    // … a sync file never

        // B has its own values for the night and a worse copy of it
        rb.outcomeRaw = Outcome.ruins.rawValue
        rb.fellAsleepAt = date(1, 23, 30); rb.asleepSeconds = 20_000; rb.sleepSourceName = "Source B"
        rb.sleepReadAt = date(2, 8, 0); rb.sleepRuleVersion = 3
        try b.context.save()
        #expect(try b.model.mergeSync([file]))
        let merged = record(b, day: 1)
        #expect(merged.outcomeRaw == Outcome.complete.rawValue)                      // A's better copy won …
        #expect(merged.fellAsleepAt == date(1, 23, 30) && merged.asleepSeconds == 20_000
                && merged.sleepSourceName == "Source B" && merged.sleepReadAt == date(2, 8, 0)
                && merged.sleepRuleVersion == 3)                                    // … B's own sleep values stayed

        // even a file that does carry sleep values (a full backup) puts none into a night that is new to the device
        try c.model.mergeSync([a.model.makeBackup()])
        #expect(c.model.records().count == 1 && !hasSleepValues(c.model.records()[0].backup))
    }

    // MARK: 5 – what never leaves a device

    @Test func debugAndRunningNightsNeverAppearInASyncFile() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        night(a, day: 1)
        a.clock.now = date(2, 12); a.model.refresh()
        a.model.startTestNight(minutes: 1, grace: 1); a.model.startNight()          // a debug night …
        a.clock.now = date(2, 12) + 40                                                     // confirming opens 30 s before its wake
        a.model.confirm(code: "1234"); a.model.acknowledgeResult()
        a.model.cancelFastNight()
        a.clock.now = date(2, 22, 25); a.model.refresh(); a.model.startNight()       // … and a real one that is running
        #expect(a.model.active != nil)
        #expect(a.model.makeBackup().nights.count == 3)
        #expect(a.model.makeBackup().nights.filter(\.isDebug).count == 1)

        let file = a.model.makeSyncFile()
        #expect(file.nights.count == 1 && file.nights.allSatisfy { !$0.isDebug && $0.finalizedAt != nil })

        // a file that does contain them (the full backup) is tolerated: those two nights are ignored
        try b.model.mergeSync([a.model.makeBackup()])
        #expect(b.model.records().count == 1 && b.model.records().allSatisfy { !$0.isDebug && $0.isFinalized })
    }

    @Test func theSystemAlarmSwitchStaysOnItsDevice() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        a.model.settings.usesSystemAlarm = false
        #expect(a.model.settings.changedAt == nil)                                   // no stamped change
        #expect(a.model.makeBackup().settings.systemAlarmOff == true)
        let file = a.model.makeSyncFile()
        #expect(file.settings.systemAlarmOff == nil)
        #expect(!String(decoding: try file.encodedForSync(), as: UTF8.self).contains("systemAlarmOff"))
        // a newer remote settings file does not switch it back on, and the other way round
        b.clock.now = date(1, 14); b.model.settings.alarmSound = .bowl
        a.clock.now = date(1, 15)
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]))
        #expect(a.model.settings.alarmSound == .bowl && !a.model.settings.usesSystemAlarm)
    }

    @Test func aSyncFileHoldsNoSyncSwitchCarriesTheHealthSwitchAsAPreferenceAndTheLanguage() throws {
        let before = Lang.current
        defer { Lang.current = before }
        let a = device(at: date(1, 12))
        a.model.language = .sk
        a.model.settings.usesHealth = true
        a.model.settings.usesSync = false
        let backup = a.model.makeBackup()
        #expect(backup.language == "sk" && backup.settings.healthOn == true && backup.settings.syncOff == true)
        let file = a.model.makeSyncFile()
        #expect(file.settings.syncOff == nil)                                        // the sync switch stays on its device
        #expect(file.settings.healthOn == true)                                      // the Health switch's POSITION travels (B2) …
        #expect(!file.nights.contains(where: hasSleepValues))                        // … the sleep values never do
        #expect(file.language == "sk")                                               // the language travels (a fresh device may adopt it)
        #expect(file.settings.wakeCode == backup.settings.wakeCode)                  // everything else is shared
        // a device that never chose a language carries none
        #expect(device(at: date(1, 12)).model.makeSyncFile().language == nil)
    }

    // MARK: 6 – spends, jokers, schedule changes

    @Test func spendsJokersAndScheduleChangesAreAUnionWithoutDuplicates() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        let silver = NightKey("2026-10-05")!
        // exact times with fractions of a second – real entries have them
        a.context.insert(CoinSpend(at: date(3, 10) + 0.5, amount: 100, reason: "rename-town"))
        a.context.insert(JokerRecord(at: date(3, 11) + 0.25, tier: .silver, firstNight: silver))
        a.context.insert(ScheduleChange(at: date(3, 12) + 0.75, from: "22:30–6:30", to: "23:00–7:00", free: true, breakKey: nil))
        b.context.insert(CoinSpend(at: date(4, 9) + 0.5, amount: 200, reason: "joker-silver"))
        b.context.insert(ScheduleChange(at: date(4, 10), from: "23:00–7:00", to: "22:00–6:00", free: false, breakKey: "2026-10-05"))
        try a.context.save(); try b.context.save()

        #expect(try a.model.mergeSync([b.model.makeSyncFile()]))
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)           // nothing new the second time
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)
        for d in [a, b] {
            #expect(d.model.spends().count == 2 && d.model.jokerRecords().count == 1 && d.model.scheduleChanges().count == 2)
            #expect(d.model.streakBreaks == [silver])                                // the paid change reached the streak
        }
        let (fa, fb) = (a.model.makeSyncFile(), b.model.makeSyncFile())
        #expect(fa.spends == fb.spends && fa.jokers == fb.jokers && fa.scheduleChanges == fb.scheduleChanges)

        // the same entries from a backup file, whose times are cut to whole seconds, are the same entries
        let cut = try BackupFile.decode(try a.model.makeBackup().encoded())
        #expect(cut.spends?.map(\.at) != a.model.makeBackup().spends?.map(\.at))      // sanity: they really are cut
        #expect(try b.model.mergeSync([cut]) == false)
        #expect(b.model.spends().count == 2 && b.model.jokerRecords().count == 1 && b.model.scheduleChanges().count == 2)

        // an entry two seconds away is another entry
        var other = a.model.makeSyncFile()
        other.spends = [.init(at: date(3, 10) + 2.5, amount: 100, reason: "rename-town")]
        #expect(try b.model.mergeSync([other]))
        #expect(b.model.spends().count == 3)
    }

    @Test func anEntryThatReallyExistsTwiceStaysTwice() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        for _ in 0..<2 { a.context.insert(CoinSpend(at: date(3, 10), amount: 50, reason: "x")) }
        b.context.insert(CoinSpend(at: date(3, 10), amount: 50, reason: "x"))
        try a.context.save(); try b.context.save()
        try b.model.mergeSync([a.model.makeSyncFile()])
        try a.model.mergeSync([b.model.makeSyncFile()])
        #expect(a.model.spends().count == 2 && b.model.spends().count == 2)
    }

    @Test func coinsNeverGoBelowZeroWhenBothDevicesSpentTheSameCoins() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        for day in 1...5 { night(a, day: day) }
        now(b, at: a.clock.now)
        try b.model.mergeSync([a.model.makeSyncFile()])
        let earned = a.model.coinsEarned
        #expect(earned > 0 && b.model.coinsEarned == earned)
        // each spends a part of what it has – together they spend more than there is
        a.context.insert(CoinSpend(at: date(7, 10), amount: earned * 6 / 10, reason: "rename-town"))
        b.context.insert(CoinSpend(at: date(7, 11), amount: earned * 6 / 10, reason: "joker-silver"))
        try a.context.save(); try b.context.save()
        #expect(a.model.coins == earned - earned * 6 / 10 && b.model.coins == a.model.coins)

        try a.model.mergeSync([b.model.makeSyncFile()])
        try b.model.mergeSync([a.model.makeSyncFile()])
        for d in [a, b] {
            #expect(d.model.coinsSpent > d.model.coinsEarned)
            #expect(d.model.coins == 0)
        }
        // the price check keeps working with a balance of 0: a paid rename is refused
        _ = a.model.renameTown("First name")                                           // the first naming is free …
        a.clock.now = date(7, 13)
        #expect(a.model.renameTown("Second name") == .renamed)                         // … so is the yearly one …
        a.clock.now = date(7, 14)
        #expect(a.model.renameCost() == .paid(RenamePolicy.price))
        #expect(a.model.renameTown("Third name") == .notEnoughCoins)                   // … the next one is not affordable
    }

    // MARK: 7 – settings

    @Test func theNewestSettingsWinOnBothDevicesAndAMergeStampsNothing() throws {
        let a = device(at: date(3, 9)), b = device(at: date(3, 9))
        b.clock.now = date(3, 10); b.model.settings.volume = 0.5                     // B changed something first …
        a.clock.now = date(3, 11)
        a.model.settings.schedule.wake = TimeOfDay(7, 0); a.model.settings.alarmSound = .ode   // … A changed the wake time later
        #expect(b.model.settings.changedAt == date(3, 10) && a.model.settings.changedAt == date(3, 11))

        now(a, b, at: date(3, 12))
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)           // B's are older: A keeps its own
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))
        #expect(a.model.settings == b.model.settings)
        #expect(b.model.settings.schedule.wake == TimeOfDay(7, 0) && b.model.settings.alarmSound == .ode)
        #expect(b.model.settings.volume == a.model.settings.volume)                  // A's value, not B's 0.5
        #expect(a.model.settings.changedAt == date(3, 11) && b.model.settings.changedAt == date(3, 11))   // no stamp of the merge
        #expect(b.model.window.wake == a.model.window.wake)                          // the phase machine follows the new schedule
    }

    @Test func aDeviceThatOnlyMergedNeverOverwritesNewerSettingsOfAnother() throws {
        let a = device(at: date(3, 9)), b = device(at: date(3, 9)), c = device(at: date(3, 9))
        a.clock.now = date(3, 11); a.model.settings.alarmSound = .ode                // A: 11:00
        c.clock.now = date(3, 11, 30); c.model.settings.volume = 0.7                 // C: 11:30
        now(b, at: date(3, 12))
        try b.model.mergeSync([a.model.makeSyncFile()])                              // B only merges, at 12:00
        #expect(b.model.settings.alarmSound == .ode && b.model.settings.changedAt == date(3, 11))

        now(c, at: date(3, 13))
        #expect(try c.model.mergeSync([b.model.makeSyncFile()]) == false)           // B's settings are still A's 11:00 ones
        #expect(c.model.settings.volume == 0.7 && c.model.settings.alarmSound == .gentle)
        #expect(try b.model.mergeSync([c.model.makeSyncFile()]))                     // and C's newer ones win on B
        #expect(b.model.settings.volume == 0.7 && b.model.settings.changedAt == date(3, 11, 30))
    }

    @Test func theHealthSwitchStaysPerDevice() throws {
        let a = device(at: date(3, 9)), b = device(at: date(3, 9))
        b.model.settings.usesHealth = true                                           // not a change that is synced …
        #expect(b.model.settings.changedAt == nil)                                   // … so it carries no stamp
        a.clock.now = date(3, 11); a.model.settings.alarmSound = .bowl
        now(b, at: date(3, 12))
        try b.model.mergeSync([a.model.makeSyncFile()])
        #expect(b.model.settings.alarmSound == .bowl && b.model.settings.usesHealth)  // B keeps its own switch
        a.model.settings.usesHealth = true
        now(a, at: date(3, 12))
        #expect(a.model.makeSyncFile().settings.healthOn == true)                    // the position travels as a preference …
        // … but a normal merge never takes it: a file with the switch OFF does not switch B's off, a file with it ON
        // does not switch another device's on
        let c = device(at: date(3, 9))
        c.model.settings.usesHealth = true
        a.model.settings.usesHealth = false
        c.clock.now = date(3, 13); c.model.settings.volume = 0.3                     // C's settings are the newest ones
        now(a, at: date(3, 12))
        try a.model.mergeSync([c.model.makeSyncFile()])
        #expect(a.model.settings.volume == 0.3 && !a.model.settings.usesHealth)       // A took C's settings, not its switch
        try c.model.mergeSync([a.model.makeSyncFile()])
        #expect(c.model.settings.usesHealth)                                         // and C's own switch stays on
        #expect(a.model.settings.changedAt == c.model.settings.changedAt)
    }

    @Test func settingsAreStampedOnlyByRealChangesOfTheUser() throws {
        let a = device(at: date(3, 9))
        #expect(a.model.settings.changedAt == nil)
        a.model.settings = a.model.settings                                          // nothing changed
        a.model.settings.alarmSound = .gentle                                        // the same value
        #expect(a.model.settings.changedAt == nil)
        a.clock.now = date(3, 10); a.model.settings.volume = 0.4
        #expect(a.model.settings.changedAt == date(3, 10) && a.model.settings.volume == 0.4)
        a.clock.now = date(3, 11); a.model.settings.nap.minutes = 60
        #expect(a.model.settings.changedAt == date(3, 11))
        // a restore is the user's own act: it counts as a change
        a.clock.now = date(3, 12)
        var b = a.model.makeBackup()
        b.settings.alarmSound = .retro
        try a.model.restore(b)
        #expect(a.model.settings.alarmSound == .retro && a.model.settings.changedAt == date(3, 12))
    }

    // MARK: 8, 9 – the profile

    @Test func theLaterRenameWinsOnBothDevicesAndALanguageThatWasChosenIsUntouched() throws {
        let before = Lang.current
        defer { Lang.current = before }
        let a = device(at: date(3, 9)), b = device(at: date(3, 9))
        a.model.language = .sk                                                        // both devices chose their own language
        b.model.language = .sk; b.model.language = .en
        a.clock.now = date(3, 10); a.model.renameTown("Alpha")
        b.clock.now = date(3, 11); b.model.renameTown("Beta")
        now(a, b, at: date(3, 12))

        #expect(try a.model.mergeSync([b.model.makeSyncFile()]))
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)           // B's name is the newer one
        #expect(a.model.townName == "Beta" && b.model.townName == "Beta")
        #expect(a.model.customTownName == "Beta")
        #expect(profile(a).townNameChangedAt == date(3, 11))                          // the stamp travelled with the name
        #expect(a.model.language == .sk && b.model.language == .en)
        #expect(profile(a).languageRaw == "sk" && profile(b).languageRaw == "en")      // a chosen language is never overwritten
        #expect(try a.model.mergeSync([b.model.makeSyncFile()]) == false)           // idempotent

        // a file without the stamp (older data) is judged by the date of the last rename
        var file = a.model.makeSyncFile()
        file.townName = "Gamma"; file.townNameChangedAt = nil; file.lastRenameAt = date(3, 11) + 1
        #expect(try b.model.mergeSync([file]))
        #expect(b.model.townName == "Gamma")
        file.townName = "Delta"; file.lastRenameAt = date(3, 11) - 100
        #expect(try b.model.mergeSync([file]) == false && b.model.townName == "Gamma")
    }

    @Test func aDeviceThatNeverChoseALanguageAdoptsTheOtherDevicesAndReallySwitches() throws {
        let before = Lang.current
        defer { Lang.current = before }
        let a = device(at: date(3, 9)), b = device(at: date(3, 9))
        a.model.language = .sk
        b.model.language = .en                                                        // the same as the default: nothing is stored, the global is English again
        #expect(profile(b).languageRaw == nil && b.model.language == .en)

        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))
        #expect(profile(b).languageRaw == "sk" && b.model.language == .sk)            // stored …
        #expect(Lang.current == .sk && L("Not synced yet") == "Zatiaľ nesynchronizované")   // … and the texts really switched
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)            // idempotent
        #expect(b.model.makeSyncFile().language == "sk")                              // and B now carries it on
    }

    @Test func aDeviceWithItsOwnLanguageKeepsItAndTwoFreshDevicesStayWithoutOne() throws {
        let before = Lang.current
        defer { Lang.current = before }
        let a = device(at: date(3, 9)), b = device(at: date(3, 9))
        a.model.language = .sk
        b.model.language = .sk; b.model.language = .en                                // B chose English on purpose
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]) == false)
        #expect(profile(b).languageRaw == "en" && b.model.language == .en && Lang.current == .en)

        let c = device(at: date(3, 9)), d = device(at: date(3, 9))                    // neither ever chose one
        #expect(try c.model.mergeSync([d.model.makeSyncFile()]) == false)
        #expect(try d.model.mergeSync([c.model.makeSyncFile()]) == false)
        #expect(profile(c).languageRaw == nil && profile(d).languageRaw == nil && c.model.language == .en)

        // a language the app does not know is ignored
        var odd = a.model.makeSyncFile()
        odd.language = "xx"
        #expect(try c.model.mergeSync([odd]) == false)
        #expect(profile(c).languageRaw == nil && c.model.language == .en)
    }

    @Test func profileDatesTakeTheEarliestOrTheLatest() throws {
        let a = device(at: date(1, 12)), b = device(at: date(3, 12)), c = device(at: date(6, 12))
        a.clock.now = date(1, 13); a.model.completeOnboarding()
        a.clock.now = date(1, 14); a.model.acknowledgeFirstNightBriefing()
        b.clock.now = date(3, 13); b.model.completeOnboarding()
        b.clock.now = date(3, 14); b.model.acknowledgeFirstNightBriefing()
        // a first naming, then (after the 10-minute typo window) the yearly free rename
        a.clock.now = date(2, 10); a.model.renameTown("A1"); a.clock.now = date(2, 12); a.model.renameTown("A2")
        b.clock.now = date(4, 10); b.model.renameTown("B1"); b.clock.now = date(4, 12); b.model.renameTown("B2")
        profile(a).schedulePromptMonth = "2026-09"; profile(b).schedulePromptMonth = "2026-10"
        #expect(profile(a).lastFreeRenameAt == date(2, 12) && profile(b).lastFreeRenameAt == date(4, 12))
        now(a, b, c, at: date(7, 12))

        try a.model.mergeSync([b.model.makeSyncFile()])
        try b.model.mergeSync([a.model.makeSyncFile()])
        try c.model.mergeSync([a.model.makeSyncFile()])
        for d in [a, b, c] {
            let p = profile(d)
            #expect(p.onboardingCompletedAt == date(1, 13) && p.firstNightBriefingAt == date(1, 14))   // the earliest
            #expect(p.changeWeekStart == date(3, 13) && d.model.changeWeekStart == date(3, 13))         // the newest change week
            #expect(d.model.onboardingDone && d.model.firstNightBriefed)
        }
        for d in [a, b] {
            let p = profile(d)
            #expect(p.lastRenameAt == date(4, 12) && p.lastFreeRenameAt == date(4, 12))                // the latest
            #expect(p.schedulePromptMonth == "2026-10" && d.model.schedulePromptAnswered == "2026-10")  // the larger one
            #expect(d.model.townName == "B2")
        }
        #expect(profile(c).schedulePromptMonth == "2026-10" && c.model.townName == "B2")                // a value beats nil
        // the monthly limit of renaming travelled too: a rename now costs coins on every device
        #expect(a.model.renameCost() == .paid(RenamePolicy.price))
    }

    // MARK: 10 – guards and order

    @Test func mergeIsRefusedDuringANightAndANewerFileIsSkipped() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        night(a, day: 1)
        let good = a.model.makeSyncFile()

        b.clock.now = date(3, 22, 25); b.model.refresh(); b.model.startNight()
        #expect(b.model.active != nil)
        #expect(throws: AppModel.BackupError.self) { try b.model.mergeSync([good]) }
        #expect(throws: AppModel.BackupError.self) { try b.model.mergeSync([]) }
        #expect(b.model.records().count == 1)                                        // only its own running night

        b.model.abandonNight(); b.model.acknowledgeResult()
        var newer = good
        newer.version = BackupFile.currentVersion + 1
        newer.nights = []
        #expect(try b.model.mergeSync([newer]) == false)                             // skipped, not an error
        #expect(try b.model.mergeSync([newer, good]))                                // the others of the call are still merged
        #expect(b.model.records().contains { $0.keyString == "2026-10-02" })
    }

    @Test func theOrderOfTheFilesDoesNotMatter() throws {
        let x = device(at: date(1, 12)), y = device(at: date(1, 12))
        night(x, day: 1); night(x, day: 2)
        night(y, day: 2); night(y, day: 3)
        let ry = record(y, day: 2)                                                    // Y's copy of the shared night is worse
        ry.outcomeRaw = Outcome.ruins.rawValue; ry.buildingId = otherBuilding(than: record(x, day: 2).buildingId)
        x.clock.now = date(5, 10); x.model.renameTown("Ex"); x.model.settings.alarmSound = .ode
        y.clock.now = date(5, 11); y.model.renameTown("Why"); y.model.settings.volume = 0.9
        x.context.insert(CoinSpend(at: date(5, 9), amount: 30, reason: "a"))
        y.context.insert(CoinSpend(at: date(5, 9, 30), amount: 40, reason: "b"))
        y.context.insert(ScheduleChange(at: date(5, 9, 40), from: "22:30–6:30", to: "23:00–7:00", free: true, breakKey: nil))
        try x.context.save(); try y.context.save()
        let (fx, fy) = (x.model.makeSyncFile(), y.model.makeSyncFile())

        let p = device(at: date(6, 12)), q = device(at: date(6, 12))
        #expect(try p.model.mergeSync([fx, fy]))
        #expect(try q.model.mergeSync([fy, fx]))
        #expect(p.model.makeSyncFile() == q.model.makeSyncFile())
        #expect(p.model.records().count == 3 && p.model.townName == "Why")
        #expect(p.model.settings.volume == 0.9 && p.model.settings.alarmSound == .gentle)   // Y's newer settings, as a whole
        #expect(nights(p).first { $0.keyString == "2026-10-03" }?.outcomeRaw == Outcome.complete.rawValue)
        // and merging everything again, in any order, changes nothing
        #expect(try p.model.mergeSync([fy, fx, fy]) == false)
        #expect(try q.model.mergeSync([fx, fy]) == false)
    }

    @Test func aMergeKeepsTheResultTheUserIsLookingAt() throws {
        let a = device(at: date(1, 12)), b = device(at: date(1, 12))
        night(a, day: 1)
        b.clock.now = date(5, 22, 25); b.model.refresh(); b.model.startNight()
        b.clock.now = date(6, 6, 31); b.model.refresh(); b.model.confirm(code: "1234")
        #expect(b.model.shownResult != nil && b.model.phase == .result)
        #expect(try b.model.mergeSync([a.model.makeSyncFile()]))
        #expect(b.model.shownResult != nil && b.model.phase == .result)             // still on the screen
        #expect(b.model.records().count == 2)
    }

    // MARK: 11 – the encodings

    @Test func theSyncEncodingKeepsFractionsOfSecondsAndTheBackupFormatDoesNot() throws {
        let a = device(at: date(1, 12))
        night(a, day: 1)
        var f = a.model.makeSyncFile()
        f.exportedAt = date(5, 12) + 0.123456
        f.nights[0].startedAt = date(1, 22, 25) + 0.987654
        f.spends = [.init(at: date(2, 3) + 0.5, amount: 5, reason: "x")]
        f.townNameChangedAt = date(2, 4) + 0.25
        f.settings.changedAt = date(2, 5) + 0.75
        let back = try BackupFile.decodeSync(try f.encodedForSync())
        #expect(back == f)                                                           // an exact round trip
        #expect(try f.encodedForSync() == f.encodedForSync())                        // sorted keys: stable bytes
        let cut = try BackupFile.decode(try f.encoded())
        #expect(cut != f && cut.nights[0].startedAt != f.nights[0].startedAt)        // the backup cuts to whole seconds
        #expect(throws: (any Error).self) { try BackupFile.decodeSync(Data("nope".utf8)) }
    }

    @Test func olderFilesWithoutTheNewFieldsStillLoad() throws {
        let a = device(at: date(1, 12))
        night(a, day: 1)
        var json = try JSONSerialization.jsonObject(with: try a.model.makeBackup().encoded()) as! [String: Any]
        json.removeValue(forKey: "townNameChangedAt"); json.removeValue(forKey: "schedulePromptMonth")
        var settings = json["settings"] as! [String: Any]
        settings.removeValue(forKey: "changedAt")
        json["settings"] = settings
        let old = try BackupFile.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(old.townNameChangedAt == nil && old.schedulePromptMonth == nil && old.settings.changedAt == nil)
        let b = device(at: date(9, 12))
        try b.model.restore(old)
        #expect(b.model.records().count == 1)
        // and the old settings JSON decodes too
        let oldSettings = try JSONSerialization.data(withJSONObject: settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: oldSettings).changedAt == nil)
    }
}
