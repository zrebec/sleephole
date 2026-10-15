import Foundation

/// The buddy's sentences about the real sky (phase 8f, owner 2026-10-15): the moon's phase and the date of the
/// solstices / equinoxes – never rise or set times. Everything is a pure function of the local calendar DAY (and the
/// hemisphere), so a whole day gives one answer and every device on the same day says the same.
public enum BuddySky {
    /// "Tonight" is evaluated at 23:00 local time of the day.
    public static let tonightHour = 23

    /// Illumination bands: full ≥ 0.97 and new ≤ 0.03 (only on the one evening that is the peak, see `isFullMoon`),
    /// crescent < 0.40, quarter 0.40…0.60, gibbous > 0.60.
    public static let fullThreshold = 0.97
    public static let newThreshold = 0.03
    public static let quarterRange = 0.40...0.60

    static func tonight(_ day: NightKey, offset: Int, _ cal: Calendar) -> Date {
        let d = day.adding(days: offset, calendar: cal)
        var c = DateComponents(year: d.year, month: d.month, day: d.day, hour: tonightHour)
        c.calendar = cal
        return cal.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// The moon at 23:00 of the day `offset` days from `day`.
    static func moon(_ day: NightKey, _ offset: Int, _ cal: Calendar) -> Astro.MoonPhase {
        Astro.moonPhase(at: tonight(day, offset: offset, cal))
    }

    /// Several evenings in a row can be ≥ 0.97 (about four), so the full moon is the evening whose illumination
    /// is the highest of its two neighbours (and ≥ 0.97); the new moon likewise the lowest (and ≤ 0.03).
    static func isFullMoon(_ day: NightKey, _ offset: Int, _ cal: Calendar) -> Bool {
        let m = moon(day, offset, cal).illuminated
        return m >= fullThreshold && m >= moon(day, offset - 1, cal).illuminated && m > moon(day, offset + 1, cal).illuminated
    }

    static func isNewMoon(_ day: NightKey, _ offset: Int, _ cal: Calendar) -> Bool {
        let m = moon(day, offset, cal).illuminated
        return m <= newThreshold && m <= moon(day, offset - 1, cal).illuminated && m < moon(day, offset + 1, cal).illuminated
    }

    public static func quarter(of m: Astro.MoonPhase) -> MoonQuarter {
        if quarterRange.contains(m.illuminated) { return m.waxing ? .firstQuarter : .lastQuarter }
        if m.illuminated < quarterRange.lowerBound { return m.waxing ? .waxingCrescent : .waningCrescent }
        return m.waxing ? .waxingGibbous : .waningGibbous
    }

    /// Whether the sun's ecliptic longitude crosses `target` degrees during the local calendar day.
    static func sunCrosses(_ target: Double, _ day: NightKey, _ cal: Calendar) -> Bool {
        func midnight(_ offset: Int) -> Date {
            let d = day.adding(days: offset, calendar: cal)
            return cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) ?? Date(timeIntervalSince1970: 0)
        }
        let a = Astro.sunLongitude(at: midnight(0)), b = Astro.sunLongitude(at: midnight(1))
        func wrap(_ x: Double) -> Double { let r = x.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }
        return wrap(target - a) < wrap(b - a)
    }

    public static func lines(day: NightKey, calendar cal: Calendar, southernHemisphere south: Bool) -> [BuddyLine] {
        var out: [BuddyLine] = []
        let tonightFull = isFullMoon(day, 0, cal)
        let tonightNew = isNewMoon(day, 0, cal)
        if tonightFull { out.append(.fullMoonTonight) }
        if tonightNew { out.append(.newMoonTonight) }
        // the longest night is the December solstice in the north (270°) and the June one in the south (90°)
        if sunCrosses(south ? 90 : 270, day, cal) { out.append(.longestNight) }
        if sunCrosses(south ? 270 : 90, day, cal) { out.append(.shortestNight) }
        if sunCrosses(0, day, cal) || sunCrosses(180, day, cal) { out.append(.equinox) }
        if !tonightFull {
            if isFullMoon(day, 1, cal) { out.append(.fullMoonTomorrow) }
            else if isFullMoon(day, 2, cal) { out.append(.fullMoonSoon(days: 2)) }
            else if isFullMoon(day, 3, cal) { out.append(.fullMoonSoon(days: 3)) }
        }
        if !tonightFull && !tonightNew { out.append(.moonPhase(quarter(of: moon(day, 0, cal)))) }
        return out
    }
}
