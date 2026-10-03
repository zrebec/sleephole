import Foundation

/// Time of day as the owner lives it: the sky follows THEIR schedule, not the sun (phase UI, reused by F5).
public enum SkyPhase: String, Sendable {
    case night, dawn, day, dusk
}

/// Which body hangs in the sky.
public enum SkyBody: String, Sendable {
    case sun, moon, none
}

/// How the moon looks: how much of the disc is lit and on which side (the southern hemisphere sees it mirrored).
public struct MoonLook: Equatable, Sendable {
    /// 0 = new … 1 = full.
    public let illuminated: Double
    public let litOnRight: Bool

    public init(illuminated: Double, litOnRight: Bool) {
        self.illuminated = illuminated
        self.litOnRight = litOnRight
    }
}

public struct SkyState: Equatable, Sendable {
    public let phase: SkyPhase
    /// 0 = night … 1 = full day.
    public let daylight: Double
    /// 0…1 strength of the sunrise / sunset colours (peaks in the middle of dawn and dusk).
    public let glow: Double
    /// 0…1 position of the sun (dawn → dusk) or the moon (night) on its arc, left to right.
    public let arc: Double
    /// What to draw on the arc. The schedule-based sky always has one: the sun by day, the moon at night.
    public let body: SkyBody
    /// The moon's real phase; nil = draw the old decorative crescent.
    public let moon: MoonLook?

    /// `body` nil = what the app has always drawn: the moon at night, the sun otherwise.
    public init(phase: SkyPhase, daylight: Double, glow: Double, arc: Double,
                body: SkyBody? = nil, moon: MoonLook? = nil) {
        self.phase = phase
        self.daylight = daylight
        self.glow = glow
        self.arc = arc
        self.body = body ?? (phase == .night ? .moon : .sun)
        self.moon = moon
    }
}

public enum Sky {
    /// Dawn starts this long before the wake time …
    public static let dawnLead: TimeInterval = 30 * 60
    /// … and lasts until this long after it.
    public static let dawnTail: TimeInterval = 60 * 60
    /// Dusk starts this long before bedtime and ends at bedtime.
    public static let duskLead: TimeInterval = 90 * 60

    public static func state(at t: Date, schedule: Schedule, calendar: Calendar) -> SkyState {
        let bed = DateComponents(hour: schedule.bedtime.hour, minute: schedule.bedtime.minute)
        let wake = DateComponents(hour: schedule.wake.hour, minute: schedule.wake.minute)
        // The last bedtime at or before t, the wake after it and the next bedtime: between two bedtimes there is
        // exactly one wake.
        let prevBed = calendar.nextDate(after: t + 1, matching: bed, matchingPolicy: .nextTime, direction: .backward)!
        let nextBed = calendar.nextDate(after: t, matching: bed, matchingPolicy: .nextTime, direction: .forward)!
        let w = calendar.nextDate(after: prevBed, matching: wake, matchingPolicy: .nextTime, direction: .forward)!

        let dayStart = w - dawnLead
        if t < dayStart {
            return SkyState(phase: .night, daylight: 0, glow: 0, arc: fraction(t, prevBed, dayStart))
        }
        // A very short day: dawn and dusk meet in the middle instead of overlapping.
        let mid = dayStart + nextBed.timeIntervalSince(dayStart) / 2
        let dawnEnd = min(w + dawnTail, mid)
        let duskStart = max(nextBed - duskLead, mid)
        let arc = fraction(t, dayStart, nextBed)
        if t < dawnEnd {
            let p = fraction(t, dayStart, dawnEnd)
            return SkyState(phase: .dawn, daylight: smooth(p), glow: sin(p * .pi), arc: arc)
        }
        if t < duskStart {
            return SkyState(phase: .day, daylight: 1, glow: 0, arc: arc)
        }
        let p = fraction(t, duskStart, nextBed)
        return SkyState(phase: .dusk, daylight: 1 - smooth(p), glow: sin(p * .pi), arc: arc)
    }

    /// The sky as it really is above `place`: the colours follow the sun's altitude (civil twilight is the
    /// dawn / dusk band), the body on the arc is the sun while it is up, else the moon while it is up, else nothing.
    public static func state(at t: Date, place: GeoPoint) -> SkyState {
        let a = Astro.sun(at: t, from: place).altitude
        let daylight = smooth(min(1, max(0, (a + 6) / 12)))
        let glow = a > -6 && a < 6 ? sin(.pi * (a + 6) / 12) : 0
        let phase: SkyPhase
        if a >= 6 {
            phase = .day
        } else if a <= -6 {
            phase = .night
        } else {
            phase = Astro.sun(at: t + 60, from: place).altitude > a ? .dawn : .dusk
        }

        if a > Astro.sunHorizon {
            let arc = Astro.sunArc(at: t, from: place).map { fraction(t, $0.rise, $0.set) } ?? 0.5
            return SkyState(phase: phase, daylight: daylight, glow: glow, arc: arc, body: .sun, moon: nil)
        }
        if Astro.moon(at: t, from: place).altitude > Astro.moonHorizon {
            let arc = Astro.moonArc(at: t, from: place).map { fraction(t, $0.rise, $0.set) } ?? 0.5
            let look = moonLook(at: t, place: place)
            return SkyState(phase: phase, daylight: daylight, glow: glow, arc: arc, body: .moon, moon: look)
        }
        return SkyState(phase: phase, daylight: daylight, glow: glow, arc: 0.5, body: SkyBody.none, moon: nil)
    }

    /// The lit side of a waxing moon is on the right in the northern hemisphere and on the left in the southern one.
    static func moonLook(at t: Date, place: GeoPoint) -> MoonLook {
        let phase = Astro.moonPhase(at: t)
        return MoonLook(illuminated: phase.illuminated, litOnRight: phase.waxing != (place.latitude < 0))
    }

    static func fraction(_ t: Date, _ a: Date, _ b: Date) -> Double {
        let span = b.timeIntervalSince(a)
        return span <= 0 ? 0 : min(1, max(0, t.timeIntervalSince(a) / span))
    }

    static func smooth(_ p: Double) -> Double { p * p * (3 - 2 * p) }
}
