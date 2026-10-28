import Foundation
import Testing
@testable import SleepCore

/// Step 11b5d: the four night skies – the id table and the pure geometry.
@Suite struct NightSkiesTests {
    @Test func tableCoversExactlyTheSkyIds() {
        #expect(NightSkies.table.map(\.id) == BoxCatalog.ids(.sky))
        #expect(Set(NightSkies.table.map(\.effect)).count == 4)
        #expect(NightSkies.effect(forId: "sky-03") == .catConstellation)
        #expect(NightSkies.effect(forId: "sky-09") == nil)
        #expect(NightSkies.effect(forId: nil) == nil)
    }

    @Test func shotsAreDeterministicAndSpaced() {
        #expect(NightSkies.shot(slot: 5) == NightSkies.shot(slot: 5))
        for slot in -3..<200 {
            let a = NightSkies.shot(slot: slot), b = NightSkies.shot(slot: slot + 1)
            let gap = b.start - a.start
            #expect(gap >= 6 && gap <= 12, "gap \(gap)")
            #expect(a.duration >= 0.8 && a.duration <= 1.2)
            #expect(a.start + a.duration < Double(slot + 1) * NightSkies.slotLength)
            #expect(a.dx < 0 && a.dy > 0)
            let end = a.head(at: 1)
            #expect(end.x > 0 && end.x < 1 && end.y > 0 && end.y < 0.3)
        }
    }

    @Test func activeShotOnlyDuringFlight() {
        let s = NightSkies.shot(slot: 7)
        #expect(NightSkies.activeShot(at: s.start - 0.01) == nil)
        #expect(abs((NightSkies.activeShot(at: s.start + s.duration / 2)?.progress ?? 0) - 0.5) < 1e-9)
        #expect(NightSkies.activeShot(at: s.start + s.duration + 0.01) == nil)
        #expect(NightSkies.activeShot(at: NightSkies.stillTime) != nil)
    }

    @Test func cometDrifts() {
        let a = NightSkies.cometHead(at: 0), b = NightSkies.cometHead(at: 120)
        #expect(a.x > b.x)
        #expect(NightSkies.cometHead(at: 10) == NightSkies.cometHead(at: 10 + NightSkies.cometPeriod) || abs(NightSkies.cometHead(at: 10).x - NightSkies.cometHead(at: 10 + NightSkies.cometPeriod).x) < 1e-9)
        #expect(a.x > 1 && NightSkies.cometHead(at: 359.9).x < 0)
    }

    @Test func catConstellationIsInTheUnitBox() {
        let c = NightSkies.cat
        #expect((10...14).contains(c.stars.count))
        for s in c.stars { #expect((0...1).contains(s.x) && (0...1).contains(s.y)) }
        for (a, b) in c.lines { #expect(c.stars.indices.contains(a) && c.stars.indices.contains(b) && a != b) }
    }
}
