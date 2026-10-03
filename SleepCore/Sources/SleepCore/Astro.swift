import Foundation

/// A place on Earth. Typed once by the owner (a city), never read from the phone's location.
public struct GeoPoint: Equatable, Hashable, Sendable, Codable {
    /// Degrees, north positive.
    public var latitude: Double
    /// Degrees, east positive.
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Where the sun and the moon really are – low-precision, dependency-free astronomy for the sky behind the screens.
/// Everything works on absolute time (`Date`), so no calendar or time zone is involved. Accuracy is chosen for a
/// picture, not for navigation: the sun within ~0.1°, the moon within ~0.5°, rise / set within a couple of minutes.
public enum Astro {
    public struct Horizontal: Equatable, Sendable {
        /// Degrees above the horizon (geometric – no atmospheric refraction).
        public let altitude: Double
        /// Degrees from north, clockwise (east = 90), 0 ..< 360.
        public let azimuth: Double
    }

    public struct MoonPhase: Equatable, Sendable {
        /// 0 = new … 1 = full.
        public let illuminated: Double
        /// Between new and full moon (the lit part grows).
        public let waxing: Bool
    }

    /// The sun's centre must be above this to count as "up" (refraction + its radius).
    public static let sunHorizon = -0.833
    /// The same for the moon's centre (its parallax of ~0.95° is already in the topocentric altitude, so only the
    /// refraction and the radius remain).
    public static let moonHorizon = 0.125

    public static func sun(at t: Date, from p: GeoPoint) -> Horizontal {
        let s = sunEquatorial(at: t)
        return horizontal(rightAscension: s.rightAscension, declination: s.declination, at: t, from: p)
    }

    /// Topocentric: the moon is so close that seen from the ground it sits up to ~1° lower than from the Earth's centre.
    public static func moon(at t: Date, from p: GeoPoint) -> Horizontal {
        let m = moonEcliptic(at: t)
        let eq = equatorial(longitude: m.longitude, latitude: m.latitude, at: t)
        let geo = horizontal(rightAscension: eq.rightAscension, declination: eq.declination, at: t, from: p)
        // The observer stands one Earth radius "above" the centre, straight along the vertical, so only the
        // altitude changes (a displacement along the vertical leaves the azimuth alone).
        let distance = 1 / sin(m.parallax * rad)           // in Earth radii
        let h = geo.altitude * rad
        let topo = atan2(distance * sin(h) - 1, distance * cos(h)) / rad
        return Horizontal(altitude: topo, azimuth: geo.azimuth)
    }

    public static func moonPhase(at t: Date) -> MoonPhase {
        let m = moonEcliptic(at: t)
        let sunLongitude = sunEcliptic(at: t)
        // Elongation of the moon from the sun as seen from the Earth, then the phase angle at the moon (Meeus 48.3):
        // the sun is ~390 moon distances away, so the two differ by a fraction of a degree – cheap to do properly.
        let cosElongation = cos(m.latitude * rad) * cos((m.longitude - sunLongitude.longitude) * rad)
        let elongation = acos(min(1, max(-1, cosElongation)))
        let moonDistanceKm = earthRadiusKm / sin(m.parallax * rad)
        let sunDistanceKm = sunLongitude.distanceAU * astronomicalUnitKm
        let phaseAngle = atan2(sunDistanceKm * sin(elongation), moonDistanceKm - sunDistanceKm * cos(elongation))
        let ahead = normalized(m.longitude - sunLongitude.longitude)
        return MoonPhase(illuminated: (1 + cos(phaseAngle)) / 2, waxing: ahead > 0 && ahead < 180)
    }

    /// While the sun is up at `t`: its last rising and its next setting. nil when it is down, or when it does not
    /// rise or set within the search window (polar day).
    public static func sunArc(at t: Date, from p: GeoPoint) -> (rise: Date, set: Date)? {
        arc(at: t, horizon: sunHorizon) { sun(at: $0, from: p).altitude }
    }

    public static func moonArc(at t: Date, from p: GeoPoint) -> (rise: Date, set: Date)? {
        arc(at: t, horizon: moonHorizon) { moon(at: $0, from: p).altitude }
    }

    // MARK: - Rising and setting

    /// 5-minute steps are shorter than any rise-to-set span we care about; the crossing is then bisected.
    static let searchStep: TimeInterval = 5 * 60
    static let searchWindow: TimeInterval = 36 * 3600

    static func arc(at t: Date, horizon: Double, altitude: (Date) -> Double) -> (rise: Date, set: Date)? {
        guard altitude(t) > horizon else { return nil }
        guard let rise = crossing(from: t, direction: -1, horizon: horizon, altitude: altitude),
              let set = crossing(from: t, direction: 1, horizon: horizon, altitude: altitude) else { return nil }
        return (rise, set)
    }

    /// Walks away from `start` (an instant where the body is up) until it is down, then bisects that last step.
    private static func crossing(from start: Date, direction: Double, horizon: Double,
                                 altitude: (Date) -> Double) -> Date? {
        var up = start
        var step = searchStep
        while step <= searchWindow {
            let probe = start.addingTimeInterval(direction * step)
            if altitude(probe) <= horizon {
                var down = probe
                for _ in 0..<12 {                           // 300 s / 2^12 < 0.1 s
                    let mid = Date(timeIntervalSince1970: (up.timeIntervalSince1970 + down.timeIntervalSince1970) / 2)
                    if altitude(mid) > horizon { up = mid } else { down = mid }
                }
                return up
            }
            up = probe
            step += searchStep
        }
        return nil
    }

    // MARK: - Maths

    private static let rad = Double.pi / 180
    private static let earthRadiusKm = 6378.14
    private static let astronomicalUnitKm = 149_597_870.7

    private static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Julian centuries since J2000.0 (the ~69 s between UT and the dynamical time are ignored: below 0.001°).
    private static func centuries(_ t: Date) -> Double {
        (t.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545) / 36525
    }

    private static func obliquity(_ T: Double) -> Double { 23.439291 - 0.0130042 * T }

    /// The sun's apparent ecliptic longitude (degrees) and distance – the NOAA / Meeus low-precision solution.
    private static func sunEcliptic(at t: Date) -> (longitude: Double, distanceAU: Double) {
        let T = centuries(t)
        let L0 = 280.46646 + T * (36000.76983 + T * 0.0003032)
        let M = (357.52911 + T * (35999.05029 - 0.0001537 * T)) * rad
        let e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
        let centre = sin(M) * (1.914602 - T * (0.004817 + 0.000014 * T))
            + sin(2 * M) * (0.019993 - 0.000101 * T) + sin(3 * M) * 0.000289
        let omega = (125.04 - 1934.136 * T) * rad
        let apparent = L0 + centre - 0.00569 - 0.00478 * sin(omega)       // nutation + aberration
        let trueAnomaly = M + centre * rad
        let distance = 1.000001018 * (1 - e * e) / (1 + e * cos(trueAnomaly))
        return (normalized(apparent), distance)
    }

    private static func sunEquatorial(at t: Date) -> (rightAscension: Double, declination: Double) {
        let T = centuries(t)
        let omega = (125.04 - 1934.136 * T) * rad
        // The true obliquity: the mean one plus the main nutation term.
        let eps = obliquity(T) + 0.00256 * cos(omega)
        return equatorial(longitude: sunEcliptic(at: t).longitude, latitude: 0, obliquity: eps)
    }

    /// The moon's geocentric ecliptic longitude / latitude and horizontal parallax, degrees – the Astronomical
    /// Almanac's low-precision series (Meeus chapter 47 cut down to its biggest terms, ~0.3° and ~0.003° in parallax).
    private static func moonEcliptic(at t: Date) -> (longitude: Double, latitude: Double, parallax: Double) {
        let T = centuries(t)
        func s(_ a: Double, _ b: Double) -> Double { sin((a + b * T) * rad) }
        func c(_ a: Double, _ b: Double) -> Double { cos((a + b * T) * rad) }
        let longitude = 218.32 + 481267.881 * T
            + 6.29 * s(135.0, 477198.87) - 1.27 * s(259.3, -413335.36) + 0.66 * s(235.7, 890534.22)
            + 0.21 * s(269.9, 954397.74) - 0.19 * s(357.5, 35999.05) - 0.11 * s(186.5, 966404.03)
        let latitude = 5.13 * s(93.3, 483202.02) + 0.28 * s(228.2, 960400.89)
            - 0.28 * s(318.3, 6003.15) - 0.17 * s(217.6, -407332.21)
        let parallax = 0.9508 + 0.0518 * c(135.0, 477198.87) + 0.0095 * c(259.3, -413335.36)
            + 0.0078 * c(235.7, 890534.22) + 0.0028 * c(269.9, 954397.74)
        return (normalized(longitude), latitude, parallax)
    }

    private static func equatorial(longitude: Double, latitude: Double, at t: Date)
        -> (rightAscension: Double, declination: Double) {
        equatorial(longitude: longitude, latitude: latitude, obliquity: obliquity(centuries(t)))
    }

    private static func equatorial(longitude: Double, latitude: Double, obliquity: Double)
        -> (rightAscension: Double, declination: Double) {
        let l = longitude * rad, b = latitude * rad, e = obliquity * rad
        let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l)) / rad
        let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l)) / rad
        return (normalized(ra), dec)
    }

    /// Altitude and azimuth of a point on the sky for an observer (geocentric direction, no refraction).
    private static func horizontal(rightAscension: Double, declination: Double, at t: Date, from p: GeoPoint)
        -> Horizontal {
        let d = t.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545
        let T = d / 36525
        // Greenwich mean sidereal time (UT) → the local hour angle of the point.
        let gmst = 280.46061837 + 360.98564736629 * d + 0.000387933 * T * T - T * T * T / 38_710_000
        let hourAngle = (gmst + p.longitude - rightAscension) * rad
        let phi = p.latitude * rad, dec = declination * rad
        let altitude = asin(min(1, max(-1, sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(hourAngle))))
        // Meeus 13.5 measures from the south, westwards; +180° turns it into "from north, clockwise".
        let south = atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(dec) * cos(phi))
        return Horizontal(altitude: altitude / rad, azimuth: normalized(south / rad + 180))
    }
}
