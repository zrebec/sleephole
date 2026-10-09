import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

/// Drives the real AppModel with a FakeClock and an in-memory store (no audio / notifications).
@MainActor
struct AppModelTests {
    let catalog = SpriteLibrary.loadFromBundle().catalog!
    let cal = Calendar.current

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    final class Harness {
        let container: ModelContainer
        let clock: FakeClock
        let model: AppModel
        init(container: ModelContainer, clock: FakeClock, model: AppModel) {
            self.container = container; self.clock = clock; self.model = model
        }
    }

    func harness(at now: Date, container: ModelContainer? = nil) -> Harness {
        let c = container ?? (try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.schedule = Schedule(bedtime: TimeOfDay(22, 30), wake: TimeOfDay(6, 30))
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: catalog, clock: clock, settings: s, servicesEnabled: false)
        return Harness(container: c, clock: clock, model: m)
    }

    /// Plays one whole night starting on `day` (bedtime 22:30, wake 6:30 next day).
    @discardableResult
    func playNight(_ h: Harness, day: Int, leaveFor: TimeInterval = 0, confirmAfterWake: TimeInterval = 60) -> Outcome? {
        h.clock.now = date(day, 22, 25); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.model.startNight()
        if leaveFor > 0 {
            h.clock.now = date(day, 23, 30); h.model.append(.leftApp)
            h.clock.now += leaveFor; h.model.append(.returned)
        }
        h.clock.now = date(day + 1, 6, 30) + confirmAfterWake; h.model.refresh()
        if confirmAfterWake <= 3600 { #expect(h.model.confirm(code: "1234")) } else { h.model.refresh() }
        let outcome = h.model.shownResult?.outcome
        h.model.acknowledgeResult()
        return outcome
    }

    @Test func startWindowIsBedtimeMinus10ToPlus5() {
        let h = harness(at: date(5, 22, 19))
        #expect(h.model.phase == .idle)
        h.clock.now = date(5, 22, 20); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.clock.now = date(5, 22, 35); h.model.refresh()
        #expect(h.model.phase == .canStart)
        h.clock.now = date(5, 22, 36); h.model.refresh()
        #expect(h.model.phase == .idle)
    }

    @Test func aPerfectNightBuildsTheFirstHouse() {
        let h = harness(at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh()
        h.model.startNight()
        #expect(h.model.phase == .building)
        #expect(h.model.active?.buildingId.hasPrefix("l1-") == true)          // first nights: level 1 only
        #expect(h.model.graceEnds == date(5, 22, 35))                        // bedtime 22:30 + 5 min (early start)
        #expect(!h.model.confirm(code: "1234"))                               // too early
        h.clock.now = date(6, 6, 30); h.model.refresh()
        #expect(h.model.phase == .alarm)
        #expect(h.model.active?.log.has(.alarmFired) == true)
        #expect(!h.model.confirm(code: "0000"))                               // wrong code
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.shownResult?.log.has(.confirmedByCode) == true)
        #expect(h.model.phase == .result)
        #expect(h.model.shownResult?.outcome == .complete)
        #expect(h.model.builtNights == 1)
        #expect(h.model.townSnapshot?.buildings.count == 1)
        #expect(h.model.townRender != nil && h.model.townVersion >= 2)
        h.model.acknowledgeResult()
        h.clock.now = date(6, 22, 20); h.model.refresh()
        #expect(h.model.phase == .canStart)                                  // next night
    }

    @Test func shakeConfirmsWithoutCode() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.clock.now = date(6, 6, 0); h.model.refresh()                        // wake − 30 min
        #expect(h.model.phase == .building)
        #expect(h.model.confirm())
        #expect(h.model.shownResult?.outcome == .complete)
        #expect(h.model.shownResult?.log.has(.confirmedByShake) == true)
    }

    @Test func leavingTheAppCollapsesTheBuilding() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, leaveFor: 30) == .ruins)
        #expect(h.model.townSnapshot?.buildings.first?.state == .ruins)
    }

    @Test func shortTripIsTolerated() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, leaveFor: 5) == .complete)
    }

    /// Regression (owner 2026-09-29): the "Vráť sa" warning was never sent.
    @Test func leavingAfterTheGraceSendsExactlyOneWarning() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.clock.now = date(5, 22, 27); h.model.append(.leftApp)          // inside the 5-min setup: no warning
        h.clock.now += 60; h.model.append(.returned)
        #expect(h.model.nudgesSent == 0)
        h.clock.now = date(5, 23, 30); h.model.append(.leftApp)          // after the setup → warning
        #expect(h.model.nudgesSent == 1)
        h.clock.now += 5; h.model.append(.returned)
        #expect(h.model.collapsedAt == nil)                               // back within 10 s after the warning
        h.clock.now = date(5, 23, 40); h.model.append(.leftApp)
        h.clock.now += 60; h.model.append(.returned)                      // too long → collapsed
        #expect(h.model.nudgesSent == 2 && h.model.collapsedAt != nil)
        h.clock.now = date(5, 23, 50); h.model.append(.leftApp)          // already collapsed: no more warnings
        #expect(h.model.nudgesSent == 2)
    }

    @Test func vibrationsOnlyWhileTheAppIsOnScreen() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        #expect(h.model.haptics == [.start])
        h.clock.now = date(5, 22, 34) + 50; h.model.append(.leftApp)     // setup: in the background → nothing
        h.clock.now = date(5, 22, 35) + 5; h.model.append(.returned)     // back 5 s after the setup: fine
        h.model.append(.locked)
        #expect(h.model.haptics == [.start] && h.model.collapsedAt == nil) // lock: iOS can't vibrate in the background
        h.clock.now = date(5, 23); h.model.append(.returned)
        h.model.append(.leftApp)                                          // after the setup → "Come back!" notifications
        #expect(h.model.nudgesSent == 1 && h.model.haptics == [.start])
        h.clock.now += 5; h.model.append(.returned)                       // back in time → relief
        #expect(h.model.haptics == [.start, .relief])
        h.clock.now = date(5, 23, 20); h.model.append(.leftApp)
        h.clock.now += 5; h.model.append(.locked)                         // locked instead of returning: no relief
        h.clock.now += 60; h.model.append(.returned)
        #expect(h.model.haptics == [.start, .relief])
        h.clock.now = date(5, 23, 30); h.model.append(.leftApp)
        h.clock.now += 60; h.model.append(.returned)                      // too late: collapsed, no relief
        #expect(h.model.collapsedAt != nil && h.model.haptics == [.start, .relief])
    }

    @Test func settingsSwitchTheSleepSoundOfTheRunningNight() {
        let h = harness(at: date(5, 22, 25))
        h.model.settings.ambience = .brownNoise
        h.model.settings.ambienceMinutes = 30
        h.model.refresh(); h.model.startNight()
        #expect(h.model.sleepSound?.ambience == .brownNoise && h.model.sleepSound?.endsAt == date(5, 22, 55))
        #expect(h.model.sleepSoundPlaying)
        h.model.settings.ambience = .rainTent                               // Settings during the night
        #expect(h.model.sleepSound?.ambience == .rainTent && h.model.sleepSound?.endsAt == date(5, 22, 55))
        h.model.stopSleepSound()
        h.model.settings.ambience = .pinkNoise                              // stopped stays stopped
        #expect(h.model.sleepSound == nil && !h.model.sleepSoundPlaying)
        h.model.playSleepSound(.whiteNoise, minutes: nil)
        h.model.settings.ambience = .silence                                // silence = off
        #expect(h.model.sleepSound == nil)
    }

    @Test func collapseIsVisibleLive() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.clock.now = date(5, 23); h.model.append(.leftApp)
        #expect(h.model.collapsedAt == date(5, 23) + 13)       // ~3 s to notice + 10 s to return
    }

    @Test func lateConfirmIsUnfinishedAndMissingConfirmIsRuins() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, confirmAfterWake: 30 * 60) == .unfinished)
        #expect(playNight(h, day: 6, confirmAfterWake: 2 * 3600) == .ruins)
    }

    @Test func abandonMakesRuins() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        h.model.abandonNight()
        #expect(h.model.shownResult?.outcome == .ruins)
        #expect(h.model.active == nil)
    }

    @Test func levelTwoUnlocksAfterFiveNights() {
        let h = harness(at: date(1, 12))
        for d in 1...4 { playNight(h, day: d) }
        #expect(h.model.levelUp == nil)
        h.clock.now = date(5, 22, 25); h.model.refresh(); h.model.startNight()
        h.clock.now = date(6, 6, 31); h.model.refresh()
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.levelUp == 2)
        #expect(h.model.builtNights == 5)
    }

    @Test func testNightsDoNotCountButTheBonusOneDoes() {
        let h = harness(at: date(5, 15))
        h.model.startTestNight(minutes: 4, grace: 20)
        #expect(h.model.phase == .canStart && h.model.debugWindow != nil)
        h.model.startNight()
        #expect(h.model.active?.isDebug == true)
        h.clock.now += 4 * 60; h.model.refresh()
        #expect(h.model.confirm())
        #expect(h.model.builtNights == 0)
        h.model.acknowledgeResult()

        h.model.nextTestNightCounts = true
        h.model.startTestNight(minutes: 15, grace: 300)
        h.model.startNight()
        #expect(h.model.nextTestNightCounts == false)                         // one-shot
        #expect(h.model.active?.isDebug == false && h.model.active?.id.hasPrefix("bonus-") == true)
        h.clock.now += 15 * 60; h.model.refresh()
        #expect(h.model.confirm())
        #expect(h.model.builtNights == 1)
        #expect(h.model.townSnapshot?.buildings.count == 1)
    }

    @Test func aQuickNightSetupEnds15SecondsAfterTheStart() {
        let h = harness(at: date(5, 15))
        let t0 = h.clock.now
        h.model.startTestNight(); h.model.startNight()
        #expect(h.model.graceEnds == t0 + 15)
        #expect(h.model.graceEnds! > t0 + 14)                                 // +14 s: still setup
        #expect(h.model.graceEnds! < t0 + 16)                                 // +16 s: after it
    }

    @Test func cancelFastNightReturnsToIdle() {
        let h = harness(at: date(5, 15))
        h.model.startTestNight()
        h.model.cancelFastNight()
        #expect(h.model.phase == .idle && h.model.debugWindow == nil)
    }

    @Test func clearNightsWipesEverything() {
        let h = harness(at: date(5, 12))
        playNight(h, day: 5)
        h.model.clearNights()
        #expect(h.model.records().isEmpty && h.model.builtNights == 0)
        #expect(h.model.townSnapshot?.buildings.isEmpty == true)
    }

    @Test func aKilledAppResumesTheNight() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh(); h.model.startNight()
        let again = harness(at: date(6, 2), container: h.container)
        #expect(again.model.active != nil)
        #expect(again.model.phase == .building)
        #expect(again.model.active?.log.has(.appLaunched) == true)
    }

    @Test func streakFlameCountsCompleteNightsInARow() {
        let h = harness(at: date(1, 12))
        #expect(h.model.streak == 0)
        playNight(h, day: 1)
        playNight(h, day: 2)
        h.clock.now = date(3, 12); h.model.refresh()
        #expect(h.model.streak == 2)
        playNight(h, day: 3, confirmAfterWake: 30 * 60)                  // unfinished: neither +1 nor break
        h.clock.now = date(4, 12); h.model.refresh()
        #expect(h.model.streak == 2)
        h.clock.now = date(6, 12); h.model.refresh()                       // a missed night breaks it
        #expect(h.model.streak == 0)
    }

    @Test func confirmingAfterTheAlarmStoppedIsUnfinished() {
        let h = harness(at: date(5, 12))
        #expect(playNight(h, day: 5, confirmAfterWake: 2 * 60 + 16) == .unfinished)   // owner test 29.09 19:06
    }

    @Test func coinsForRealNightsOnly() {
        let h = harness(at: date(1, 12))
        h.clock.now = date(1, 22, 25); h.model.refresh(); h.model.startNight()
        h.clock.now = date(2, 6, 31); h.model.refresh(); h.model.confirm(code: "1234")
        // complete +100, no pause +30 and the achievement "First building" +50
        #expect(h.model.coins == 180 && h.model.lastReward == 180 && h.model.newAchievements == [.firstBuilding])
        #expect(h.model.lastUndisturbedBonus == 30)
        h.model.acknowledgeResult()
        #expect(h.model.newAchievements.isEmpty)
        playNight(h, day: 2, confirmAfterWake: 30 * 60)                   // unfinished +50 (no bonus)
        #expect(h.model.coins == 230)
        h.clock.now = date(3, 15)
        h.model.startTestNight(); h.model.startNight()                    // debug: nothing
        h.clock.now += 240; h.model.refresh(); h.model.confirm()
        #expect(h.model.coins == 230 && h.model.lastReward == 0 && h.model.newAchievements.isEmpty)
        h.model.acknowledgeResult()
        h.model.nextTestNightCounts = true                                // the counted test night pays
        h.model.startTestNight(); h.model.startNight()
        h.clock.now += 240; h.model.refresh(); h.model.confirm()
        #expect(h.model.coins == 360)                                     // +100 +30
    }

    @Test func seventhNightPaysTheStreakBonus() {
        let h = harness(at: date(1, 12))
        for d in 1...6 { playNight(h, day: d) }
        h.clock.now = date(7, 22, 25); h.model.refresh(); h.model.startNight()
        h.clock.now = date(8, 6, 31); h.model.refresh(); h.model.confirm(code: "1234")
        // 100 + streak bonus 200 + achievements ("7 nights in a row", maybe a random first L2 building)
        let bonus = h.model.newAchievements.reduce(0) { $0 + $1.reward }
        #expect(h.model.newAchievements.contains(.streak7) && h.model.lastStreakBonus == 200)
        // the 7th night may already build level 2 (pays 120)
        let level = catalog[h.model.shownResult!.buildingId]!.level
        #expect(h.model.lastReward == Economy.completeReward(level: level) + 200 + bonus + PausePolicy.undisturbedBonus)
        let nights = h.model.coreResults().reduce(0) { $0 + Economy.reward($1.outcome, level: catalog[$1.buildingId ?? ""]?.level ?? 1) }
        #expect(h.model.coins == nights + 7 * PausePolicy.undisturbedBonus + 200 + Achievements.coins(h.model.achievements))
    }

    @Test func sleepSoundDuringTheNight() {
        let h = harness(at: date(5, 22, 25)); h.model.refresh()
        h.model.playSleepSound(.rainTent, minutes: 15)                         // no night yet → ignored
        #expect(h.model.sleepSound == nil)
        h.model.startNight()
        h.clock.now = date(5, 22, 50)
        h.model.playSleepSound(.rainTent, minutes: 15)
        #expect(h.model.sleepSound?.ambience == .rainTent && h.model.sleepSound?.endsAt == date(5, 23, 5))
        #expect(h.model.settings.ambience == .rainTent && h.model.settings.ambienceMinutes == 15)
        h.model.playSleepSound(.pinkNoise, minutes: nil)                   // all night
        #expect(h.model.sleepSound?.endsAt == nil)
        h.model.stopSleepSound()
        #expect(h.model.sleepSound == nil)
        h.model.playSleepSound(.silence, minutes: 5)
        #expect(h.model.sleepSound == nil)
        #expect(h.model.collapsedAt == nil)                                // staying in the app is fine
    }

    @Test func napWindowOnePerDayAndMessages() {
        let h = harness(at: date(5, 12, 59))
        let was12h = Fmt.systemUses12h
        defer { Fmt.systemUses12h = was12h }
        Fmt.systemUses12h = false
        #expect(h.model.napBlockReason()?.contains("13:00–15:00") == true)
        Fmt.systemUses12h = true
        #expect(h.model.napBlockReason()?.replacingOccurrences(of: "\u{202F}", with: " ").contains("1:00 PM–3:00 PM") == true)
        h.model.language = .sk
        #expect(h.model.napBlockReason() == "Teraz nemôžeš odpočívať (13:00–15:00).")   // SK is always 24 h
        h.model.language = .en
        h.clock.now = date(5, 15, 0)                                        // edge: exactly the window end
        #expect(h.model.napBlockReason() == nil)
        h.model.startNap()
        #expect(h.model.active?.isNap == true && h.model.phase == .building)
        #expect(h.model.active?.wake == date(5, 15, 30))                    // 30 min default
        #expect(h.model.graceEnds == date(5, 15, 2))                         // 2 min setup
        #expect(h.model.napBlockReason() == "A night is in progress.")
        #expect(!h.model.confirm(code: "1234"))                             // only at the end
        h.clock.now = date(5, 15, 30); h.model.refresh()
        #expect(h.model.phase == .alarm)
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.shownResult?.isNap == true && h.model.shownResult?.outcome == .complete)
        #expect(h.model.coins == 100 && h.model.lastReward == 100 && h.model.levelUp == nil)   // + "First nap"
        #expect(h.model.newAchievements == [.firstNap])
        #expect(h.model.napSummary.count == 1 && h.model.napSummary.coins == 50)
        #expect(h.model.builtNights == 0 && h.model.townSnapshot?.buildings.isEmpty == true && h.model.streak == 0)
        h.model.acknowledgeResult()
        #expect(h.model.napBlockReason() == "You've already had today's nap 😴")
        h.clock.now = date(5, 18, 0)
        #expect(h.model.napBlockReason() != nil)
    }

    @Test func sixtyMinuteNapFromTheEdgeAndAnInterruptedNap() {
        let h = harness(at: date(5, 15, 0))
        h.model.settings.nap.minutes = 60
        h.model.startNap()
        #expect(h.model.active?.wake == date(5, 16, 0))                     // 15:00 → 16:00
        h.clock.now = date(5, 15, 10); h.model.append(.leftApp)
        h.clock.now = date(5, 15, 12); h.model.append(.returned)
        #expect(h.model.collapsedAt != nil)
        h.clock.now = date(5, 16, 1); h.model.refresh(); h.model.confirm()
        #expect(h.model.shownResult?.outcome == .ruins && h.model.coins == 0)
        // a nap never blocks the night
        h.model.acknowledgeResult()
        h.clock.now = date(5, 22, 25); h.model.refresh()
        #expect(h.model.phase == .canStart)
    }

    @Test func settingsChangesArePersisted() {
        let h = harness(at: date(5, 12))
        h.model.settings.alarmSound = .alert
        #expect(AppSettings.load().alarmSound == .alert)
    }

    // MARK: jokers (owner 2026-10-02)

    @Test func automaticBronzeKeepsTheStreakAfterAMissedNight() {
        let h = harness(at: date(5, 12))
        playNight(h, day: 5)
        playNight(h, day: 6)
        // the night 7→8 is missed (the app is not used), back on 8→9
        playNight(h, day: 8)
        h.clock.now = date(9, 12); h.model.refresh()
        #expect(h.model.streak == 3)
        #expect(h.model.jokerState.uses.map(\.tier) == [.bronze] && h.model.jokerState.uses[0].automatic)
        // each kind once a month: the automatic bronze uses up only the bronze one
        #expect(h.model.jokerBlock(.bronze) == .alreadyUsedThisMonth && h.model.jokerBlock(.silver) != .alreadyUsedThisMonth)
        #expect(h.model.coreResults().contains { $0.outcome == .excused })
        let excused = h.model.coreResults().first { $0.outcome == .excused }!.key
        #expect(h.model.coinsEarned(for: excused) == 0)                    // the protected night pays nothing
    }

    @Test func aGoldJokerCostsCoinsAndProtectsAHoliday() {
        let h = harness(at: date(5, 12))
        for d in 2...6 { playNight(h, day: d) }
        h.clock.now = date(7, 12); h.model.refresh()
        let poor = h.model.coins
        #expect(h.model.jokerBlock(.silver) == .notEnoughCoins(missing: 1000 - poor))
        for d in 7...12 { playNight(h, day: d) }                            // 11 nights + a 7-night bonus
        h.clock.now = date(13, 12); h.model.refresh()
        let before = h.model.coins
        #expect(before >= 1000 && before < 5000)
        #expect(h.model.jokerBlock(.gold) == .notEnoughCoins(missing: 5000 - before))
        #expect(h.model.jokerBlock(.silver) == nil)
        #expect(h.model.jokerFirstNight == NightKey(date: date(14, 6, 30), calendar: cal))    // tonight
        h.model.useJoker(.silver)
        #expect(h.model.coins == before - 1000 && h.model.spends().last?.reason == "joker-silver")
        #expect(h.model.activeJoker?.tier == .silver)
        h.clock.now = date(16, 12); h.model.refresh()                     // three nights away (keys 14–16)
        #expect(h.model.streak == 11)
        #expect(h.model.jokerBlock(.silver) == .alreadyUsedThisMonth)       // the silver one is used up, the bronze one is not
        #expect(h.model.jokerBlock(.bronze) == nil)
        // a backup keeps the joker
        let b = h.model.makeBackup()
        #expect(b.jokers?.count == 1)
        let other = harness(at: date(16, 12))
        try? other.model.restore(b)
        #expect(other.model.streak == 11)
    }

    // MARK: night pause + budget (D17, audit B4)

    @Test func aPauseLetsYouLeaveForTenMinutes() {
        let h = harness(at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh(); h.model.startNight()
        #expect(h.model.pauseBlock() == .setup(until: date(5, 22, 35)))
        h.model.startPause()                                               // ignored during the setup
        #expect(h.model.pauseEnds() == nil)
        h.clock.now = date(6, 2, 0)
        #expect(h.model.pauseBlock() == nil && h.model.nextPausePrice == 0)
        h.model.startPause()
        #expect(h.model.pauseEnds() == date(6, 2, 10) && h.model.active?.pauses == 1)
        #expect(h.model.pauseBlock() == .running(until: date(6, 2, 10)))
        h.clock.now = date(6, 2, 1); h.model.append(.leftApp)
        #expect(h.model.nudgesSent == 0)                                   // no "come back" inside a pause
        h.clock.now = date(6, 2, 9); h.model.append(.returned)
        #expect(h.model.collapsedAt == nil && h.model.awayBudgetUse()?.used == 0)
        h.clock.now = date(6, 2, 30)
        #expect(h.model.nextPausePrice == 50)                              // the second one costs
        let coinsBefore = h.model.coins
        #expect(h.model.pauseBlock() == .notEnoughCoins(missing: 50 - coinsBefore))
        h.clock.now = date(6, 6, 31); h.model.refresh()
        #expect(h.model.confirm(code: "1234"))
        #expect(h.model.shownResult?.outcome == .complete && h.model.shownResult?.result?.pauses == 1)
        #expect(h.model.lastUndisturbedBonus == 0 && h.model.lastReward == 100 + 50)       // no +30; +50 first building
        #expect(NightReport(log: h.model.shownResult!.log).pauses.count == 1)
    }

    @Test func theSecondPauseCostsFiftyCoins() {
        let h = harness(at: date(1, 12))
        for d in 1...2 { playNight(h, day: d) }                            // 2 × 130 + achievements
        h.clock.now = date(3, 22, 25); h.model.refresh(); h.model.startNight()
        h.clock.now = date(4, 1, 0); h.model.startPause()
        h.clock.now = date(4, 3, 0)
        let before = h.model.coins
        h.model.startPause()
        #expect(h.model.coins == before - 50 && h.model.spends().last?.reason.hasPrefix("pause-") == true)
        #expect(h.model.active?.pauses == 2)
        h.clock.now = date(4, 4, 0)
        #expect(h.model.nextPausePrice == 100)
    }

    @Test func shortTripsShareOneBudgetPerNight() {
        let h = harness(at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh(); h.model.startNight()
        for i in 0..<2 {                                                   // 2 × 12 s = 24 s of 30 s
            h.clock.now = date(6, 1, i); h.model.append(.leftApp)
            #expect(h.model.lastNudgeSeconds == 10)
            h.clock.now += 12; h.model.append(.returned)
        }
        #expect(h.model.nudgesSent == 2 && h.model.collapsedAt == nil)
        #expect(h.model.awayBudgetUse()?.used == 24 && h.model.awayBudgetUse()?.budget == 30)
        #expect(h.model.awayBudgetState(at: date(6, 1, 9)) == .low)        // 6 s left: less than one full trip
        h.clock.now = date(6, 1, 10); h.model.append(.leftApp)             // budget left → a full trip, the full warning
        #expect(h.model.nudgesSent == 3 && h.model.lastNudgeSeconds == 10)
        h.clock.now += 8; h.model.append(.returned)
        #expect(h.model.collapsedAt == nil && h.model.awayBudgetUse()?.used == 32)
        #expect(h.model.awayBudgetState() == .spent)
        h.clock.now = date(6, 1, 20); h.model.append(.leftApp)             // the budget is used up → no warning, down at once
        #expect(h.model.nudgesSent == 3 && h.model.collapsedAt == date(6, 1, 20))
    }

    @Test func theBudgetStateFollowsTheTrips() {
        let h = harness(at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh(); h.model.startNight()
        #expect(h.model.awayBudgetState() == .fine)
        h.clock.now = date(6, 1, 0); h.model.append(.leftApp)
        h.clock.now += 12; h.model.append(.returned)
        h.clock.now = date(6, 1, 1); h.model.append(.leftApp)
        h.clock.now += 12; h.model.append(.returned)
        #expect(h.model.awayBudgetState() == .low)                         // 24 s used, 6 s left
        h.clock.now = date(6, 1, 2); h.model.append(.leftApp)
        h.clock.now += 12; h.model.append(.returned)
        #expect(h.model.awayBudgetState() == .spent)
    }

    @Test func nightsFromBeforeThePauseKeepTheOldRules() {
        let h = harness(at: date(5, 12))
        h.clock.now = date(5, 22, 25); h.model.refresh(); h.model.startNight()
        let rec = h.model.active!
        rec.pauses = nil                                                   // as stored by an older build
        #expect(rec.rules.awayBudget == nil)
        for i in 0..<5 {                                                   // five short trips in a row
            h.clock.now = date(6, 1, i); h.model.append(.leftApp)
            h.clock.now += 7; h.model.append(.returned)
        }
        #expect(h.model.collapsedAt == nil && h.model.awayBudgetUse() == nil)
        h.clock.now = date(6, 6, 31); h.model.refresh(); h.model.confirm(code: "1234")
        #expect(h.model.shownResult?.outcome == .complete)
        #expect(h.model.lastUndisturbedBonus == 0 && h.model.shownResult?.result?.pauses == nil)
        // a backup keeps "old night" (nil) and "new night without a pause" (0) apart
        let b = h.model.makeBackup()
        #expect(b.nights.first?.pauses == nil)
        let decoded = try? BackupFile.decode(try! b.encoded())
        #expect(decoded?.nights.first?.pauses == nil)
    }

    // MARK: alarm safety + expiry (audit B1–B3)

    @Test func backupAlarmIsAChainOfNotifications() {
        #expect(Notifications.backupAlarmOffsets == [30, 60, 90, 120, 150])
        #expect(Notifications.backupAlarmIds == ["alarm-backup", "alarm-backup-2", "alarm-backup-3", "alarm-backup-4", "alarm-backup-5"])
    }

    @Test func expiryIsReadFromTheProvisioningProfile() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CreationDate</key><date>2026-09-29T12:23:43Z</date>
        <key>ExpirationDate</key><date>2026-10-06T12:23:43Z</date>
        </dict></plist>
        """
        // a real profile wraps the plist in a signed binary envelope
        let blob = Data([0x30, 0x82, 0x1F, 0x00]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x0B, 0x77])
        let expiry = try #require(AppExpiry.expirationDate(inProvision: blob))
        #expect(expiry == ISO8601DateFormatter().date(from: "2026-10-06T12:23:43Z"))
        #expect(AppExpiry.expirationDate(inProvision: Data("garbage".utf8)) == nil)
        #expect(AppExpiry.date == nil && !AppExpiry.isSoon(at: Date()))      // the simulator has no profile
    }

    // MARK: petting the cat (plan P2b)

    @Test func pettingTheCatCyclesPurrArchWinkAndVibratesAccordingly() throws {
        let h = harness(at: date(5, 12))
        #expect(h.model.petBuddy() == .purr)
        #expect(h.model.petBuddy() == .arch)
        #expect(h.model.petBuddy() == .wink)
        #expect(h.model.petBuddy() == .purr)
        #expect(h.model.haptics == [.purr, .pet, .pet, .purr])
        h.model.petBuddy()                                                  // the result may be ignored
        #expect(h.model.haptics.count == 5)
    }

    /// Presentation only: no coins, no rules, nothing stored in the settings or the backup, a new session starts at purr.
    @Test func pettingTheCatStoresNothingAndCostsNothing() throws {
        let h = harness(at: date(5, 12))
        let coins = h.model.coins
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys                              // dictionaries must not reorder
        let backup = try encoder.encode(h.model.makeBackup())
        let settings = h.model.settings
        for _ in 0..<7 { h.model.petBuddy() }
        #expect(h.model.coins == coins)
        #expect(try encoder.encode(h.model.makeBackup()) == backup)
        #expect(h.model.settings == settings)
        #expect(h.model.phase == .idle && h.model.active == nil)
        let next = harness(at: date(5, 12), container: h.container)       // "a new session": the same store, a new model
        #expect(next.model.petBuddy() == .purr)
    }
}
