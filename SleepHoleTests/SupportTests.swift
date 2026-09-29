import Foundation
import SleepCore
import SpriteKit
import Testing
import UIKit
@testable import SleepHole

@MainActor
struct SupportTests {
    let sprites = SpriteLibrary.loadFromBundle()

    @Test func spriteLibraryLoadsAndCaches() throws {
        let catalog = try #require(sprites.catalog)
        #expect(catalog.entries.count == 190)
        let a = try #require(sprites.image(for: "l3-police"))
        #expect(sprites.image(for: "l3-police") === a)
        #expect(sprites.image(for: "nope") == nil)
        #expect(SpriteLibrary.loadFromBundle(Bundle(for: BundleToken.self)).catalog == nil)
    }

    @Test func everyAlarmSoundShipsInTheBundle() {
        for s in AppSettings.AlarmSound.allCases {
            #expect(Bundle.main.url(forResource: s.fileName, withExtension: nil) != nil, "\(s)")
            #expect(!s.title.isEmpty && s.rampSeconds >= 0 && s.id == s.rawValue)
        }
        #expect(AppSettings().alarmSound == .gentle)                          // owner's default
    }

    @Test func settingsRoundTripAndWakeCode() throws {
        var s = AppSettings()
        s.ambience = .silence
        s.schedule = Schedule(bedtime: TimeOfDay(21, 0), wake: TimeOfDay(4, 30))
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let code = AppSettings.randomCode()
        #expect(code.count == 4 && code.allSatisfy(\.isNumber))
    }

    @Test func nightRecordKeepsItsLog() {
        let w = Schedule().window(containing: Date(), calendar: .current)
        let r = NightRecord(window: w, buildingId: "l1-house-a-0", isDebug: false, setupGrace: 300)
        #expect(r.id == w.key.description && r.result == nil && !r.isFinalized)
        r.append(.started, at: w.bedtime)
        r.append(.confirmed, at: w.wake)
        #expect(r.log.events.count == 2 && r.startedAt == w.bedtime && r.confirmedAt == w.wake)
        #expect(r.rules.setupGrace == 300 && r.window == w)
        r.outcomeRaw = Outcome.complete.rawValue
        #expect(r.result?.outcome == .complete)
        let d = NightRecord(window: w, buildingId: "x", isDebug: true, setupGrace: 20)
        #expect(d.id.hasPrefix("debug-"))
        let b = NightRecord(window: w, buildingId: "x", isDebug: false, setupGrace: 300, idPrefix: "bonus")
        #expect(b.id.hasPrefix("bonus-"))
    }

    @Test func populationCountsHomesNotRuins() throws {
        let catalog = try #require(sprites.catalog)
        let k = NightKey("2026-10-01")!
        let town = TownBuilder.build(results: [
            NightResult(key: k, outcome: .complete, buildingId: "l1-house-a-0"),
            NightResult(key: k.adding(days: 1, calendar: .current), outcome: .ruins, buildingId: "l1-block-a-0"),
            NightResult(key: k.adding(days: 2, calendar: .current), outcome: .unfinished, buildingId: "l4-sky-a-0"),
        ], catalog: catalog)
        #expect(TownStats.population(town, catalog: catalog) == 4 + 150)
        #expect([1, 2][safe: 5] == nil && [1, 2][safe: 1] == 2)
    }

    @Test func alphaLookup() throws {
        let img = try #require(sprites.image(for: "t-grass-a"))
        let cg = try #require(img.cgImage)
        #expect(img.alpha(atX: cg.width / 2, y: cg.height / 2) > 0.9)       // tile centre
        #expect(img.alpha(atX: 1, y: 1) < 0.1)                               // transparent corner
        #expect(img.alpha(atX: -1, y: 0) == 0)
    }

    @Test func probeLogPersistsAndExports() {
        let log = ProbeLog()
        log.clear()
        log.add("hello")
        #expect(ProbeLog().entries.last?.text == "hello")
        #expect(log.exportText.contains("hello"))
        log.clear()
        #expect(ProbeLog().entries.isEmpty)
    }
}

private final class BundleToken {}
