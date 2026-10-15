import Foundation
import Testing
@testable import SleepCore

/// Calm hours (CARE-2a). Default night: bedtime 22:30, wake 06:30 (8 h).
@Suite struct CalmHoursTests {
    let rules = SleepRules()
    let wake = nightMinutes

    private func clean(start: Double = 3, extra: [(Double, NightEventKind)] = []) -> NightLog {
        log([(start, .started), (start + 1, .locked)] + extra + [(wake, .alarmFired), (wake + 1, .confirmed)])
    }

    @Test func cleanNightPaysAllWholeHours() {
        // started 22:33 → setup ends 22:38 → hours 22:38 … 05:38 = 7 whole hours (05:38–06:38 is past the wake)
        #expect(CalmHours.count(log: clean(), rules: rules) == .init(calm: 7, total: 7))
    }

    @Test func lastPartialHourIsNotCounted() {
        #expect(CalmHours.hours(of: clean(), rules: rules).count == 7)
        let late = clean(start: 5)      // setup ends 22:40 → 22:40…05:40 is still 7; 06:40 is past
        #expect(CalmHours.count(log: late, rules: rules).total == 7)
        let veryLate = log([(5, .started), (wake, .confirmed)])
        // a wake time 6 h 55 min after the anchor → 6 hours
        let shorter = NightWindow(key: night.key, bedtime: night.bedtime, wake: night.bedtime + 6.9 * 3600)
        #expect(CalmHours.count(log: NightLog(window: shorter, buildingId: "x", events: veryLate.events), rules: rules).total == 6)
    }

    @Test func tripSpoilsOnlyItsHour() {
        // 02:00–02:00:08 (minutes 210) lies in the hour 01:38–02:38 only
        let l = clean(extra: [(210, .leftApp), (210.1, .returned)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 6, total: 7))
    }

    @Test func tripAcrossBoundarySpoilsBoth() {
        // hours start 22:38 + n h; the boundary 23:38 is minute 68
        let l = clean(extra: [(67.9, .leftApp), (68.1, .returned)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 5, total: 7))
    }

    @Test func callDoesNotSpoil() {
        let l = clean(extra: [(100, .callStarted), (101, .leftApp), (110, .returned), (111, .callEnded)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 7, total: 7))
    }

    @Test func usedLockScreenSpoilsEvenInGentleMode() {
        var gentle = rules
        gentle.lockScreenCollapses = false
        let l = clean(extra: [(150, .usedLockScreen), (151, .locked)])
        #expect(CalmHours.count(log: l, rules: gentle) == .init(calm: 6, total: 7))
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 6, total: 7))
    }

    @Test func glanceAndScreenOnDoNotSpoil() {
        let l = clean(extra: [(150, .screenOn), (150.1, .ownerRecognised), (150.2, .screenOff)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 7, total: 7))
    }

    @Test func pauseSpoilsTheHoursItOverlaps() {
        // a 10-minute pause at minute 63 (until 73) crosses the boundary at minute 68
        let l = clean(extra: [(63, .pauseStarted)])
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 5, total: 7))
    }

    @Test func closedAppSpoilsUntilReopened() {
        let l = clean(extra: [(130, .closedByOwner), (190, .appLaunched)])      // minute 130 and 190 in hours 2 and 3
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 5, total: 7))
    }

    @Test func earlyStartIsAnchoredAtBedtimePlusSetup() {
        let l = log([(-100, .started), (-99, .locked), (wake, .confirmed)])
        // anchor 22:35 (not 21:55 + 15 min, not the bedtime) → 7 whole hours
        #expect(CalmHours.hours(of: l, rules: rules).first?.0 == night.bedtime + rules.setupGrace)
        #expect(CalmHours.count(log: l, rules: rules) == .init(calm: 7, total: 7))
    }

    @Test func earlyAndNormalStartCountTheSameHours() {
        let early = CalmHours.count(log: log([(-100, .started), (-99, .locked), (wake, .confirmed)]), rules: rules)
        let normal = CalmHours.count(log: log([(-5, .started), (-4, .locked), (wake, .confirmed)]), rules: rules)
        #expect(early == normal && early.total == 7)
    }

    @Test func noStartNoHours() {
        #expect(CalmHours.count(log: log([]), rules: rules) == .init(calm: 0, total: 0))
    }

    // MARK: ledger

    private func result(_ o: Outcome, calm: Int?, total: Int? = 7) -> NightResult {
        NightResult(key: night.key, outcome: o, buildingId: nil, pauses: 1, calmHours: calm, calmHoursTotal: total)
    }

    @Test func ledgerPaysCompleteAndUnfinished() {
        let c = Economy.ledger([result(.complete, calm: 7)], calendar: bratislava)[0]
        #expect(c.calmHours == 7 && c.calmBonus == 35 && c.coins == 100 + 35)
        let u = Economy.ledger([result(.unfinished, calm: 4)], calendar: bratislava)[0]
        #expect(u.calmBonus == 20 && u.coins == 50 + 20)
    }

    @Test func ledgerPaysNothingForRuinsMissedExcused() {
        for o in [Outcome.ruins, .missed, .excused] {
            let e = Economy.ledger([result(o, calm: 5)], calendar: bratislava)[0]
            #expect(e.calmBonus == 0 && e.coins == 0)
        }
    }

    @Test func oldNightKeepsItsCoins() {
        let e = Economy.ledger([result(.complete, calm: nil, total: nil)], calendar: bratislava)[0]
        #expect(e.calmHours == 0 && e.calmBonus == 0 && e.coins == 100)
    }

    @Test func oldStoredResultDecodesWithoutCalmHours() throws {
        let data = try JSONEncoder().encode(result(.complete, calm: 3))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "calmHours"); json.removeValue(forKey: "calmHoursTotal")
        let old = try JSONDecoder().decode(NightResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.calmHours == nil && old.calmHoursTotal == nil)
    }
}
