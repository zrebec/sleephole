import Foundation
import Testing
@testable import SleepCore

/// Reference values come from an independent implementation (PyEphem, geometric: pressure 0), see
/// `tools/astro/reference.py`. NOTE: that script asks PyEphem for the sun's UPPER limb at the -0:50 horizon, so its
/// sunrises are ~1–2 min later and its sunsets ~1–2 min earlier than "the centre at -0.833°" (what `Astro` computes;
/// against PyEphem's `use_center=True` it agrees to a few seconds). The 3-minute tolerance below covers that.
private let places: [String: GeoPoint] = [
    "bratislava": GeoPoint(latitude: 48.1486, longitude: 17.1077),
    "sydney": GeoPoint(latitude: -33.8688, longitude: 151.2093),
    "quito": GeoPoint(latitude: -0.1807, longitude: -78.4678),
    "tromso": GeoPoint(latitude: 69.6492, longitude: 18.9553),
]

private func utc(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

/// Smallest difference of two compass bearings.
private func bearingGap(_ a: Double, _ b: Double) -> Double {
    let d = (a - b).truncatingRemainder(dividingBy: 360)
    return abs(d > 180 ? d - 360 : d < -180 ? d + 360 : d)
}

private struct PositionRow: Sendable {
    let place: String, utc: String
    let sunAlt: Double, sunAz: Double, moonAlt: Double, moonAz: Double
    init(_ place: String, _ utc: String, _ sunAlt: Double, _ sunAz: Double, _ moonAlt: Double, _ moonAz: Double) {
        self.place = place; self.utc = utc
        self.sunAlt = sunAlt; self.sunAz = sunAz; self.moonAlt = moonAlt; self.moonAz = moonAz
    }
}

private let positions: [PositionRow] = [
    PositionRow("bratislava", "2026-10-03T10:00:00Z", 37.05, 167.27, 25.50, 282.13),
    PositionRow("bratislava", "2026-10-03T16:30:00Z", -1.34, 265.27, -15.92, 353.88),
    PositionRow("bratislava", "2026-10-03T19:00:00Z", -25.78, 294.68, -11.89, 26.57),
    PositionRow("bratislava", "2026-06-21T11:00:00Z", 65.25, 183.63, 4.24, 95.35),
    PositionRow("bratislava", "2026-12-21T11:00:00Z", 18.37, 182.51, -9.69, 39.27),
    PositionRow("bratislava", "2026-03-20T06:00:00Z", 9.98, 101.56, 6.98, 85.53),
    PositionRow("bratislava", "2027-01-15T22:00:00Z", -60.24, 330.33, 16.74, 272.33),
    PositionRow("sydney", "2026-10-03T10:00:00Z", -25.04, 245.97, -60.60, 93.68),
    PositionRow("sydney", "2026-10-03T16:30:00Z", -35.47, 125.81, 10.67, 46.40),
    PositionRow("sydney", "2026-10-03T19:00:00Z", -6.76, 99.68, 26.84, 16.74),
    PositionRow("sydney", "2026-06-21T11:00:00Z", -50.12, 266.78, 30.08, 294.14),
    PositionRow("sydney", "2026-12-21T11:00:00Z", -19.44, 221.86, 31.77, 3.16),
    PositionRow("sydney", "2026-03-20T06:00:00Z", 25.14, 288.16, 27.97, 305.60),
    PositionRow("sydney", "2027-01-15T22:00:00Z", 35.02, 93.30, -54.48, 113.98),
    PositionRow("quito", "2026-10-03T10:00:00Z", -15.68, 94.25, 58.24, 27.66),
    PositionRow("quito", "2026-10-03T16:30:00Z", 80.89, 115.93, 9.82, 297.20),
    PositionRow("quito", "2026-10-03T19:00:00Z", 60.45, 261.80, -22.18, 298.42),
    PositionRow("quito", "2026-06-21T11:00:00Z", -3.67, 66.52, -88.17, 86.23),
    PositionRow("quito", "2026-12-21T11:00:00Z", -2.66, 113.47, -34.79, 298.53),
    PositionRow("quito", "2026-03-20T06:00:00Z", -80.34, 91.92, -80.76, 338.03),
    PositionRow("quito", "2027-01-15T22:00:00Z", 19.46, 247.69, 68.07, 46.15),
]

private struct DayRow: Sendable {
    let place: String, rise: String, set: String
    init(_ place: String, _ rise: String, _ set: String) { self.place = place; self.rise = rise; self.set = set }
}

private let sunDays: [DayRow] = [
    DayRow("bratislava", "2026-10-03T04:51:48Z", "2026-10-03T16:28:33Z"),
    DayRow("bratislava", "2026-06-21T02:49:16Z", "2026-06-21T18:57:28Z"),
    DayRow("bratislava", "2026-12-21T06:37:09Z", "2026-12-21T15:02:03Z"),
    DayRow("bratislava", "2026-03-20T04:53:13Z", "2026-03-20T17:05:42Z"),
    DayRow("sydney", "2026-10-02T19:28:50Z", "2026-10-03T08:00:20Z"),
    DayRow("sydney", "2026-06-20T20:58:31Z", "2026-06-21T06:55:14Z"),
    DayRow("sydney", "2026-12-20T18:39:09Z", "2026-12-21T09:06:54Z"),
    DayRow("quito", "2026-10-03T10:58:27Z", "2026-10-03T23:07:12Z"),
    DayRow("quito", "2026-06-21T11:11:13Z", "2026-06-21T23:20:14Z"),
]

@Suite struct AstroTests {
    // MARK: positions

    @Test(arguments: positions) private func sunMatchesTheReference(_ row: PositionRow) {
        let s = Astro.sun(at: utc(row.utc), from: places[row.place]!)
        #expect(abs(s.altitude - row.sunAlt) < 0.3, "altitude \(s.altitude) vs \(row.sunAlt)")
        if abs(row.sunAlt) <= 80 {                              // near the zenith the azimuth is ill-conditioned
            #expect(bearingGap(s.azimuth, row.sunAz) < 0.3, "azimuth \(s.azimuth) vs \(row.sunAz)")
        }
    }

    @Test(arguments: positions) private func moonMatchesTheReference(_ row: PositionRow) {
        let m = Astro.moon(at: utc(row.utc), from: places[row.place]!)
        #expect(abs(m.altitude - row.moonAlt) < 1.5, "altitude \(m.altitude) vs \(row.moonAlt)")
        if abs(row.moonAlt) <= 80 {
            #expect(bearingGap(m.azimuth, row.moonAz) < 2.5, "azimuth \(m.azimuth) vs \(row.moonAz)")
        }
    }

    @Test func azimuthStaysInRangeAndAltitudeIsAnAngle() {
        let start = utc("2026-01-01T00:00:00Z")
        for place in places.values {
            for i in 0..<400 {
                let t = start + Double(i) * 23 * 3600 + 777
                for h in [Astro.sun(at: t, from: place), Astro.moon(at: t, from: place)] {
                    #expect(h.azimuth >= 0 && h.azimuth < 360)
                    #expect(h.altitude >= -90 && h.altitude <= 90)
                }
            }
        }
    }

    @Test func theSunRisesInTheEastAndSetsInTheWest() {
        let bra = places["bratislava"]!
        #expect(Astro.sun(at: utc("2026-03-20T05:00:00Z"), from: bra).azimuth < 120)       // just after sunrise
        #expect(Astro.sun(at: utc("2026-03-20T17:00:00Z"), from: bra).azimuth > 240)       // just before sunset
        let noon = Astro.sun(at: utc("2026-10-03T11:00:00Z"), from: bra)
        #expect(bearingGap(noon.azimuth, 180) < 15)                                          // due south at noon
    }

    // MARK: sunrise and sunset

    @Test(arguments: sunDays) private func sunArcMatchesTheReference(_ day: DayRow) throws {
        let rise = utc(day.rise), set = utc(day.set)
        let arc = try #require(Astro.sunArc(at: rise + set.timeIntervalSince(rise) / 2, from: places[day.place]!))
        #expect(abs(arc.rise.timeIntervalSince(rise)) < 180, "rise \(arc.rise) vs \(rise)")
        #expect(abs(arc.set.timeIntervalSince(set)) < 180, "set \(arc.set) vs \(set)")
    }

    @Test func sunArcIsTheSameFromAnywhereInsideTheDay() throws {
        let bra = places["bratislava"]!
        let early = try #require(Astro.sunArc(at: utc("2026-10-03T05:00:00Z"), from: bra))
        let late = try #require(Astro.sunArc(at: utc("2026-10-03T16:25:00Z"), from: bra))
        #expect(abs(early.rise.timeIntervalSince(late.rise)) < 2 && abs(early.set.timeIntervalSince(late.set)) < 2)
    }

    @Test func theBisectedCrossingsReallyTouchTheHorizon() throws {
        for (name, instant) in [("bratislava", "2026-10-03T11:00:00Z"), ("sydney", "2026-12-21T00:00:00Z"),
                                ("quito", "2026-06-21T17:00:00Z")] {
            let p = places[name]!
            let arc = try #require(Astro.sunArc(at: utc(instant), from: p))
            #expect(abs(Astro.sun(at: arc.rise, from: p).altitude - Astro.sunHorizon) < 0.02)
            #expect(abs(Astro.sun(at: arc.set, from: p).altitude - Astro.sunHorizon) < 0.02)
            #expect(arc.rise < utc(instant) && utc(instant) < arc.set)
        }
    }

    @Test func noArcWhileTheSunIsDown() {
        let night = utc("2026-10-03T19:00:00Z")                  // Bratislava, 21:00 local
        #expect(Astro.sun(at: night, from: places["bratislava"]!).altitude < Astro.sunHorizon)
        #expect(Astro.sunArc(at: night, from: places["bratislava"]!) == nil)
        #expect(Astro.sunArc(at: utc("2026-10-03T16:30:00Z"), from: places["bratislava"]!) == nil)   // just set
    }

    @Test func midnightSunHasNoArc() {
        let tromso = places["tromso"]!
        for hour in [0, 6, 12, 18, 22] {
            let t = utc("2026-06-21T00:00:00Z") + Double(hour) * 3600
            #expect(Astro.sun(at: t, from: tromso).altitude > Astro.sunHorizon)
            #expect(Astro.sunArc(at: t, from: tromso) == nil)
        }
    }

    @Test func polarNightHasNoSunAtAll() {
        let tromso = places["tromso"]!
        for hour in [0, 6, 12, 18, 22] {
            let t = utc("2026-12-21T00:00:00Z") + Double(hour) * 3600
            #expect(Astro.sun(at: t, from: tromso).altitude < Astro.sunHorizon)
            #expect(Astro.sunArc(at: t, from: tromso) == nil)
        }
    }

    // MARK: moon phase

    @Test(arguments: [
        ("2026-10-03T12:00:00Z", 0.508), ("2026-10-18T12:00:00Z", 0.485), ("2026-11-02T12:00:00Z", 0.429),
        ("2026-10-10T12:00:00Z", 0.001), ("2026-10-26T04:00:00Z", 0.998),
        ("2026-08-12T17:45:00Z", 0.000), ("2026-03-03T11:30:00Z", 1.000),
    ] as [(String, Double)]) func moonPhaseMatchesTheReference(_ iso: String, _ expected: Double) {
        let phase = Astro.moonPhase(at: utc(iso))
        #expect(abs(phase.illuminated - expected) < 0.03, "\(phase.illuminated) vs \(expected)")
        #expect(phase.illuminated >= 0 && phase.illuminated <= 1)
    }

    @Test(arguments: [
        ("2026-10-03T12:00:00Z", false), ("2026-10-18T12:00:00Z", true), ("2026-11-02T12:00:00Z", false),
    ] as [(String, Bool)]) func theMoonWaxesBetweenNewAndFull(_ iso: String, _ waxing: Bool) {
        #expect(Astro.moonPhase(at: utc(iso)).waxing == waxing)
    }

    @Test func aWholeMonthFlipsOnlyAtNewAndFull() {
        // Illuminated grows while waxing and shrinks while waning, a full cycle every ~29.5 days.
        var previous = Astro.moonPhase(at: utc("2026-10-10T12:00:00Z"))      // new moon
        var flips = 0
        for day in 1...30 {
            let now = Astro.moonPhase(at: utc("2026-10-10T12:00:00Z") + Double(day) * 86400)
            if now.waxing == previous.waxing { #expect((now.illuminated > previous.illuminated) == now.waxing) }
            else { flips += 1 }
            previous = now
        }
        #expect(flips == 2 || flips == 3)                                    // full moon, new moon (+ the next full)
    }

    // MARK: moonrise and moonset

    @Test func moonArcMatchesTheReference() throws {
        let bra = places["bratislava"]!
        let a = try #require(Astro.moonArc(at: utc("2026-10-20T18:00:00Z"), from: bra))
        #expect(abs(a.rise.timeIntervalSince(utc("2026-10-20T13:40:00Z"))) < 600, "rise \(a.rise)")
        #expect(abs(a.set.timeIntervalSince(utc("2026-10-20T23:25:33Z"))) < 600, "set \(a.set)")

        // The moon sets the next morning here: the arc crosses the date line of a day.
        let b = try #require(Astro.moonArc(at: utc("2026-10-27T22:00:00Z"), from: bra))
        #expect(abs(b.rise.timeIntervalSince(utc("2026-10-27T15:59:05Z"))) < 600, "rise \(b.rise)")
        #expect(abs(b.set.timeIntervalSince(utc("2026-10-28T08:36:30Z"))) < 600, "set \(b.set)")
    }

    @Test func noMoonArcWhileTheMoonIsDown() {
        let bra = places["bratislava"]!
        let t = utc("2026-10-03T19:00:00Z")                      // the moon rises at 21:00:46Z
        #expect(Astro.moon(at: t, from: bra).altitude < Astro.moonHorizon)
        #expect(Astro.moonArc(at: t, from: bra) == nil)
    }

    @Test func theBisectedMoonCrossingsTouchTheHorizon() throws {
        let bra = places["bratislava"]!
        let arc = try #require(Astro.moonArc(at: utc("2026-10-27T22:00:00Z"), from: bra))
        #expect(abs(Astro.moon(at: arc.rise, from: bra).altitude - Astro.moonHorizon) < 0.05)
        #expect(abs(Astro.moon(at: arc.set, from: bra).altitude - Astro.moonHorizon) < 0.05)
    }

    // MARK: type

    @Test func geoPointSurvivesJSON() throws {
        let p = GeoPoint(latitude: 48.1486, longitude: 17.1077)
        let back = try JSONDecoder().decode(GeoPoint.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }
}
