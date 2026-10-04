import Foundation
import Testing
@testable import SleepCore

@Suite struct SkyTests {
    func sky(_ h: Int, _ m: Int = 0, schedule: Schedule = defaultSchedule, day: Int = 15) -> SkyState {
        Sky.state(at: at(2026, 10, day, h, m), schedule: schedule, calendar: bratislava)
    }

    @Test func phasesFollowTheDefaultSchedule() {          // 22:30 → 06:30
        #expect(sky(3).phase == .night)
        #expect(sky(5, 59).phase == .night)
        #expect(sky(6, 0).phase == .dawn)                  // wake − 30 min
        #expect(sky(7, 29).phase == .dawn)
        #expect(sky(7, 30).phase == .day)                  // wake + 60 min
        #expect(sky(14).phase == .day)
        #expect(sky(21, 0).phase == .dusk)                 // bedtime − 90 min
        #expect(sky(22, 29).phase == .dusk)
        #expect(sky(22, 30).phase == .night)
        #expect(sky(23, 59).phase == .night)
    }

    @Test func daylightAndGlowAreContinuous() {
        #expect(sky(3).daylight == 0)
        #expect(sky(12).daylight == 1 && sky(12).glow == 0)
        let midDawn = sky(6, 45)
        #expect(abs(midDawn.daylight - 0.5) < 0.01 && midDawn.glow > 0.99)
        let midDusk = sky(21, 45)
        #expect(abs(midDusk.daylight - 0.5) < 0.01 && midDusk.glow > 0.99)
        #expect(sky(22, 29).daylight < 0.01)
    }

    @Test func arcRunsLeftToRight() {
        #expect(sky(22, 30).arc == 0)                       // moon rises at bedtime
        #expect(abs(sky(2, 15).arc - 0.5) < 0.01)           // 22:30 … 06:00 → middle at 02:15
        #expect(sky(6, 0).arc == 0)                         // sun rises at dawn
        #expect(sky(14).arc > 0.4 && sky(14).arc < 0.6)
    }

    @Test func bedtimeAfterMidnightWorks() {
        let late = Schedule(bedtime: TimeOfDay(0, 30), wake: TimeOfDay(8, 0))
        #expect(sky(23, 30, schedule: late).phase == .dusk)
        #expect(sky(1, schedule: late).phase == .night)
        #expect(sky(7, 45, schedule: late).phase == .dawn)
        #expect(sky(12, schedule: late).phase == .day)
    }

    @Test func shortDayDawnAndDuskMeetInTheMiddle() {
        // awake only 06:00 … 08:00: dawn 05:30 … 06:45, dusk 06:45 … 08:00
        let short = Schedule(bedtime: TimeOfDay(8, 0), wake: TimeOfDay(6, 0))
        #expect(sky(6, 30, schedule: short).phase == .dawn)
        #expect(sky(7, 0, schedule: short).phase == .dusk)
        #expect(sky(12, schedule: short).phase == .night)
    }

    @Test func dstNightsStillHaveOneWake() {                 // 25 Oct 2026: clocks go back at 03:00
        #expect(sky(2, 30, day: 25).phase == .night)
        #expect(sky(6, 15, day: 25).phase == .dawn)
        #expect(sky(12, day: 25).phase == .day)
    }
}

// MARK: - The real sky above a place

private let bra = GeoPoint(latitude: 48.1486, longitude: 17.1077)
private let sydney = GeoPoint(latitude: -33.8688, longitude: 151.2093)
private let tromso = GeoPoint(latitude: 69.6492, longitude: 18.9553)
private let quito = GeoPoint(latitude: -0.1807, longitude: -78.4678)

private func utc(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

@Suite struct RealSkyTests {
    func real(_ iso: String, _ place: GeoPoint = bra) -> SkyState { Sky.state(at: utc(iso), place: place) }

    @Test func middayIsDayWithTheSunOnItsArc() {
        let s = real("2026-10-03T10:00:00Z")                     // sun at 37°; it rose 04:52Z and sets 16:29Z
        #expect(s.phase == .day)
        #expect(s.daylight == 1 && s.glow == 0)
        #expect(s.body == .sun && s.moon == nil)
        #expect(abs(s.arc - 0.44) < 0.02)
    }

    @Test func sunsetIsDuskWithTheMoonAtTheLeftEnd() {
        let s = real("2026-10-03T16:30:00Z")                     // sun at −1.3°, just set (16:27Z); the real moon is still below
        #expect(s.phase == .dusk)
        #expect(s.body == .moon && s.moon != nil && s.arc < 0.02)
        #expect(s.glow > 0.9)
        #expect(s.daylight > 0.2 && s.daylight < 0.5)
    }

    @Test func darkNightHasTheMoonAsTheClock() {
        let s = real("2026-10-03T19:00:00Z")                     // sun −26°, the real moon only rises at 21:00Z
        #expect(s.phase == .night)
        #expect(s.daylight == 0 && s.glow == 0)
        #expect(s.body == .moon && s.moon != nil)
        #expect(abs(s.arc - 0.205) < 0.02)                        // 2 h 33 min of the 12 h 28 min night
    }

    @Test func theMoonIsInTheMiddleAtTheMiddleOfTheNight() {
        let s = real("2026-10-03T22:40:00Z")                     // sunset 16:27Z … sunrise 04:55Z: the middle is 22:41Z
        #expect(s.phase == .night && s.body == .moon)
        #expect(abs(s.arc - 0.5) < 0.03)
    }

    @Test func beforeSunriseIsDawnAndTheMoonIsAtTheRightEnd() {
        let s = real("2026-10-04T04:45:00Z")                     // sunrise 04:55Z, the sun is climbing
        #expect(s.phase == .dawn)
        #expect(s.glow > 0 && s.daylight > 0 && s.daylight < 0.5)
        #expect(s.body == .moon && s.moon != nil && s.arc > 0.97)  // the sun is still below its horizon
    }

    @Test func theMoonHasItsRealPhaseEvenWhenTheRealMoonIsBelowTheHorizon() throws {
        let t = utc("2026-10-03T19:00:00Z")
        #expect(Astro.moon(at: t, from: bra).altitude < Astro.moonHorizon)       // it rises at 21:00Z
        let look = try #require(real("2026-10-03T19:00:00Z").moon)
        #expect(look == Sky.moonLook(at: t, place: bra))
        #expect(abs(look.illuminated - Astro.moonPhase(at: t).illuminated) < 1e-9)
    }

    @Test func fullMoonNightShowsTheMoonOnItsArc() throws {
        let s = real("2026-10-27T22:00:00Z")                     // two days after full moon, up since 15:59Z
        #expect(s.phase == .night && s.daylight == 0 && s.glow == 0)
        #expect(s.body == .moon)
        let look = try #require(s.moon)
        #expect(look.illuminated > 0.9)
        #expect(s.arc > 0 && s.arc < 1)
        #expect(look.litOnRight == false)                         // waning, seen from the north
    }

    @Test func winterNightHasTheMoonToo() {
        #expect(real("2027-01-15T22:00:00Z").body == .moon)
    }

    @Test func daylightAndGlowFollowTheSunsAltitude() {
        for iso in ["2026-10-03T04:30:00Z", "2026-10-03T05:15:00Z", "2026-10-03T06:00:00Z", "2026-10-03T16:30:00Z",
                    "2026-10-03T17:00:00Z", "2026-06-21T03:30:00Z"] {
            let a = Astro.sun(at: utc(iso), from: bra).altitude
            let s = real(iso)
            let p = min(1, max(0, (a + 6) / 12))
            #expect(abs(s.daylight - Sky.smooth(p)) < 1e-9, "\(iso) altitude \(a)")
            #expect(abs(s.glow - sin(.pi * p)) < 1e-9)
        }
    }

    @Test func dawnAndDuskFollowTheDirectionOfTheSun() {
        // The same altitude band, two directions.
        #expect(real("2026-10-03T05:00:00Z").phase == .dawn)
        #expect(real("2026-10-03T16:00:00Z").phase == .dusk)
        #expect(real("2026-10-03T07:00:00Z").phase == .day)
        #expect(real("2026-10-03T18:00:00Z").phase == .night)
    }

    @Test func bodyIsTheSunWhileItIsUpAndTheMoonOtherwise() {
        let start = utc("2026-10-20T00:00:00Z")
        for i in 0..<288 {                                        // five-minute steps over one day
            let t = start + Double(i) * 300
            let s = Sky.state(at: t, place: bra)
            let sunUp = Astro.sun(at: t, from: bra).altitude > Astro.sunHorizon
            #expect(s.body == (sunUp ? .sun : .moon))             // never nothing, whatever the real moon does
            #expect((s.moon != nil) == !sunUp)
            #expect(s.arc >= 0 && s.arc <= 1)
        }
    }

    /// Two days in 10-minute steps: the body is never `.none`, and the sun (by day) and the moon (by night) only ever
    /// move to the right until the other one takes over.
    @Test(arguments: [bra, sydney, quito]) func somethingIsAlwaysOnTheArcAndItNeverGoesBackwards(_ place: GeoPoint) {
        let start = utc("2026-10-03T00:00:00Z")
        var previous: SkyState?
        var moons = 0, suns = 0
        for i in 0...288 {
            let s = Sky.state(at: start + Double(i) * 600, place: place)
            #expect(s.body != SkyBody.none)
            #expect(s.arc >= 0 && s.arc <= 1)
            if let p = previous, p.body == s.body {
                #expect(s.arc >= p.arc, "step \(i) \(s.body): \(p.arc) → \(s.arc)")
            }
            moons += s.body == .moon ? 1 : 0
            suns += s.body == .sun ? 1 : 0
            previous = s
        }
        #expect(moons > 0 && suns > 0)                            // both really happened in 48 hours
    }

    @Test func eachNightStartsAtTheLeftEndAndEndsAtTheRight() {
        let start = utc("2026-10-03T00:00:00Z")
        for place in [bra, sydney, quito] {
            var previous: SkyState?
            for i in 0...288 {
                let s = Sky.state(at: start + Double(i) * 600, place: place)
                if let p = previous, p.body != s.body {
                    // the hand-over (sun → moon at sunset, moon → sun at sunrise): the old one is at its far end
                    #expect(p.arc > 0.95, "\(p.body) \(p.arc)")
                    #expect(s.arc < 0.05, "\(s.body) \(s.arc)")
                }
                previous = s
            }
        }
    }

    // MARK: the moon seen from the other hemisphere

    @Test func theLitSideOfTheMoonMirrorsInTheSouth() {
        // Waxing (first quarter on 18 Oct 2026): the moon is up in both places at these instants.
        let waxingSouth = utc("2026-10-18T10:00:00Z"), waxingNorth = utc("2026-10-18T19:00:00Z")
        #expect(Astro.moonPhase(at: waxingSouth).waxing && Astro.moonPhase(at: waxingNorth).waxing)
        #expect(Astro.moon(at: waxingSouth, from: sydney).altitude > Astro.moonHorizon)
        #expect(Astro.moon(at: waxingNorth, from: bra).altitude > Astro.moonHorizon)
        #expect(Sky.moonLook(at: waxingSouth, place: sydney).litOnRight == false)
        #expect(Sky.moonLook(at: waxingNorth, place: bra).litOnRight == true)

        // Waning (3 Nov 2026): the other way round.
        let waningSouth = utc("2026-11-03T18:00:00Z"), waningNorth = utc("2026-11-03T02:00:00Z")
        #expect(!Astro.moonPhase(at: waningSouth).waxing && !Astro.moonPhase(at: waningNorth).waxing)
        #expect(Astro.moon(at: waningSouth, from: sydney).altitude > Astro.moonHorizon)
        #expect(Astro.moon(at: waningNorth, from: bra).altitude > Astro.moonHorizon)
        #expect(Sky.moonLook(at: waningSouth, place: sydney).litOnRight == true)
        #expect(Sky.moonLook(at: waningNorth, place: bra).litOnRight == false)
    }

    @Test func theMirroredMoonReachesTheSkyState() {
        let south = Sky.state(at: utc("2026-10-18T10:00:00Z"), place: sydney)     // 21:00 local, sun −22°
        #expect(south.body == .moon && south.phase == .night)
        #expect(south.moon?.litOnRight == false)
        let north = Sky.state(at: utc("2026-10-18T19:00:00Z"), place: bra)
        #expect(north.body == .moon && north.moon?.litOnRight == true)
        #expect(abs((south.moon?.illuminated ?? 0) - 0.48) < 0.05)
    }

    // MARK: continuity and the poles

    /// Twilight is fastest near the equator: 15° per hour is 2.5° per 10-minute step, and the smoothstep over the
    /// 12° band is at most 1.5× as steep as a straight line – so the equator and the equinoxes need more room than
    /// the owner's latitude (a property of the specified formula, not a bug).
    @Test(arguments: [(bra, 0.25), (tromso, 0.25), (sydney, 0.32), (quito, 0.32)] as [(GeoPoint, Double)])
    func daylightNeverJumps(_ place: GeoPoint, _ limit: Double) {
        for day in ["2026-03-20T00:00:00Z", "2026-06-21T00:00:00Z", "2026-12-21T00:00:00Z"] {
            let start = utc(day)
            var previous = Sky.state(at: start, place: place).daylight
            for i in 1...144 {                                    // a whole day in 10-minute steps
                let s = Sky.state(at: start + Double(i) * 600, place: place)
                #expect(s.daylight >= 0 && s.daylight <= 1)
                #expect(s.glow >= 0 && s.glow <= 1)
                #expect(abs(s.daylight - previous) < limit, "\(day) step \(i): \(previous) → \(s.daylight)")
                previous = s.daylight
            }
        }
    }

    @Test func midnightSunHangsInTheMiddleOfItsArc() {
        for iso in ["2026-06-21T00:00:00Z", "2026-06-21T12:00:00Z"] {
            let s = real(iso, tromso)
            #expect(s.body == .sun && s.arc == 0.5)               // it never rises or sets: no arc to walk along
            #expect(s.moon == nil)
        }
    }

    @Test func polarNightHasTheMoonInTheMiddleOfItsArc() {
        for iso in ["2026-12-21T00:00:00Z", "2026-12-21T10:30:00Z", "2026-12-21T20:00:00Z"] {
            let s = real(iso, tromso)                             // the sun never rises: no night arc to walk along
            #expect(s.body == .moon && s.arc == 0.5)
            #expect(s.moon != nil)
        }
    }

    @Test func polarNightNoonIsOnlyTwilight() {
        let s = real("2026-12-21T10:30:00Z", tromso)              // the sun peaks at −3° around local noon
        #expect(s.body == .moon)
        #expect(s.glow > 0.5 && s.daylight < 0.5)
        #expect(s.phase == .dawn || s.phase == .dusk)
    }

    // MARK: the old initializer keeps working

    @Test func oldInitializerDrawsTheMoonAtNightAndTheSunOtherwise() {
        for phase in [SkyPhase.night, .dawn, .day, .dusk] {
            let s = SkyState(phase: phase, daylight: 0.5, glow: 0.5, arc: 0.5)
            #expect(s.body == (phase == .night ? .moon : .sun))
            #expect(s.moon == nil)                                // nil = the old decorative crescent
        }
        let explicit = SkyState(phase: .night, daylight: 0, glow: 0, arc: 0.2, body: SkyBody.none)
        #expect(explicit.body == .none)
        let withLook = SkyState(phase: .night, daylight: 0, glow: 0, arc: 0.2,
                                moon: MoonLook(illuminated: 0.3, litOnRight: true))
        #expect(withLook.body == .moon && withLook.moon?.illuminated == 0.3)
    }

    @Test func scheduleSkyIsUnchangedByTheNewFields() {
        let s = Sky.state(at: at(2026, 10, 15, 14), schedule: defaultSchedule, calendar: bratislava)
        #expect(s.body == .sun && s.moon == nil)
        let n = Sky.state(at: at(2026, 10, 15, 3), schedule: defaultSchedule, calendar: bratislava)
        #expect(n.body == .moon && n.moon == nil)
    }
}
