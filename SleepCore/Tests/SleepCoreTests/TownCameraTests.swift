import Foundation
import Testing
@testable import SleepCore

struct TownCameraTests {
    let bounds = SceneRect(minX: -1000, minY: -800, maxX: 1200, maxY: 900)

    @Test func roundTrip() throws {
        let c = TownCamera(scale: 2.5, x: 10, y: -20, seenBuilding: "2026-10-20")
        let back = try JSONDecoder().decode(TownCamera.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func restoreClampsScaleAndCentre() {
        let r = TownCamera(scale: 99, x: 5000, y: -5000).restored(in: bounds, minScale: 0.6, maxScale: 10)
        #expect(r.scale == 10 && r.x == 1200 && r.y == -800)
        let s = TownCamera(scale: 0.01, x: 0, y: 0).restored(in: bounds, minScale: 0.6, maxScale: 10)
        #expect(s.scale == 0.6 && s.x == 0 && s.y == 0)
        #expect(TownCamera(scale: .nan, x: 0, y: 0).restored(in: bounds, minScale: 0.6, maxScale: 10).scale == 0.6)
    }

    @Test func restoreKeepsTheSeenBuilding() {
        let r = TownCamera(scale: 2, x: 0, y: 0, seenBuilding: "a").restored(in: bounds, minScale: 0.6, maxScale: 10)
        #expect(r.seenBuilding == "a")
    }

    @Test func glideDecisions() {
        var c = TownCamera(scale: 2, x: 0, y: 0, seenBuilding: "2026-10-20")
        let newBuilding = c.noteNewest("2026-10-21")
        #expect(newBuilding)                                 // a new building → glide
        #expect(c.seenBuilding == "2026-10-21")
        let same = c.noteNewest("2026-10-21")
        #expect(!same)                                       // the same → none
        let empty = c.noteNewest(nil)
        #expect(!empty && c.seenBuilding == "2026-10-21")    // an empty town → none, memory kept
        var fresh = TownCamera(scale: 2, x: 0, y: 0)
        let first = fresh.noteNewest("2026-10-21")
        #expect(!first && fresh.seenBuilding == "2026-10-21")   // nothing remembered → remember, no glide
        var gone = TownCamera(scale: 2, x: 0, y: 0, seenBuilding: "2026-09-01")
        let unknown = gone.noteNewest("2026-05-05")
        #expect(unknown)                                     // the remembered one is gone → glide
    }

    @Test func clampReachesTheTopOfTheBounds() {
        // the camera centre can be brought to the top edge of the tallest sprite, whatever the scale
        let p = TownRender.clamp(ScenePoint(x: 0, y: 1e9), to: bounds)
        #expect(p.y == bounds.maxY)
    }
}
