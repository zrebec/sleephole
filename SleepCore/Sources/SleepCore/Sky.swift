import Foundation

/// Time of day as the owner lives it: the sky follows THEIR schedule, not the sun (phase UI, reused by F5).
public enum SkyPhase: String, Sendable {
    case night, dawn, day, dusk
}

public struct SkyState: Equatable, Sendable {
    public let phase: SkyPhase
    /// 0 = night … 1 = full day.
    public let daylight: Double
    /// 0…1 strength of the sunrise / sunset colours (peaks in the middle of dawn and dusk).
    public let glow: Double
    /// 0…1 position of the sun (dawn → dusk) or the moon (night) on its arc, left to right.
    public let arc: Double

    public init(phase: SkyPhase, daylight: Double, glow: Double, arc: Double) {
        self.phase = phase
        self.daylight = daylight
        self.glow = glow
        self.arc = arc
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

    static func fraction(_ t: Date, _ a: Date, _ b: Date) -> Double {
        let span = b.timeIntervalSince(a)
        return span <= 0 ? 0 : min(1, max(0, t.timeIntervalSince(a) / span))
    }

    static func smooth(_ p: Double) -> Double { p * p * (3 - 2 * p) }
}
