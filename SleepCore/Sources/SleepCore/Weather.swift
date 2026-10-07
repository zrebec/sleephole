import Foundation

/// What the sky looks like, reduced to what the town can draw.
public enum WeatherKind: String, Codable, Sendable, CaseIterable { case clear, cloudy, fog, rain, thunder, snow }

/// The weather over the owner's city right now (source-independent: WeatherKit, Yr, Open-Meteo … all map into this).
public struct WeatherNow: Codable, Equatable, Sendable {
    public var temperatureC: Double
    public var kind: WeatherKind
    /// 0…1 how hard it rains / snows; 0 for the dry kinds.
    public var intensity: Double
    /// 0…1.
    public var cloudCover: Double
    public var isDaylight: Bool
    public var snowOnGround: Bool
    public var observedAt: Date

    public init(temperatureC: Double, kind: WeatherKind, intensity: Double, cloudCover: Double, isDaylight: Bool,
                snowOnGround: Bool, observedAt: Date) {
        self.temperatureC = temperatureC
        self.kind = kind
        self.intensity = intensity
        self.cloudCover = cloudCover
        self.isDaylight = isDaylight
        self.snowOnGround = snowOnGround
        self.observedAt = observedAt
    }
}

/// One past hour, for the "snow lies" rule.
public struct WeatherHour: Equatable, Sendable {
    public var date: Date
    public var temperatureC: Double
    public var snowfallMm: Double

    public init(date: Date, temperatureC: Double, snowfallMm: Double) {
        self.date = date
        self.temperatureC = temperatureC
        self.snowfallMm = snowfallMm
    }
}

/// Weather rules: pure and testable. The condition table is keyed by `WeatherKit.WeatherCondition.rawValue`.
public enum WeatherRules {
    /// A successful value is not asked for again sooner.
    public static let refreshInterval: TimeInterval = 30 * 60
    public static let retryAfterFailure: TimeInterval = 5 * 60
    /// An older value is not shown at all.
    public static let staleAfter: TimeInterval = 90 * 60
    /// °C: above it snow melts.
    public static let thawAbove = 2.0
    /// Snow that fell since the last thaw and adds up to this many mm lies on the ground.
    public static let snowCoverFromMm = 5.0

    private static let table: [String: (WeatherKind, Double)] = [
        "clear": (.clear, 0), "mostlyClear": (.clear, 0), "hot": (.clear, 0), "frigid": (.clear, 0),
        "breezy": (.clear, 0), "windy": (.clear, 0),
        "partlyCloudy": (.cloudy, 0), "mostlyCloudy": (.cloudy, 0), "cloudy": (.cloudy, 0),
        "foggy": (.fog, 0), "haze": (.fog, 0), "smoky": (.fog, 0), "blowingDust": (.fog, 0),
        "drizzle": (.rain, 0.25), "freezingDrizzle": (.rain, 0.25), "sunShowers": (.rain, 0.3),
        "rain": (.rain, 0.6), "freezingRain": (.rain, 0.6), "hail": (.rain, 0.8), "heavyRain": (.rain, 1),
        "tropicalStorm": (.rain, 1), "hurricane": (.rain, 1),
        "isolatedThunderstorms": (.thunder, 0.6), "scatteredThunderstorms": (.thunder, 0.7),
        "thunderstorms": (.thunder, 0.9), "strongStorms": (.thunder, 1),
        "flurries": (.snow, 0.25), "sunFlurries": (.snow, 0.25), "sleet": (.snow, 0.5), "wintryMix": (.snow, 0.5),
        "snow": (.snow, 0.6), "blowingSnow": (.snow, 0.7), "heavySnow": (.snow, 1), "blizzard": (.snow, 1),
    ]

    public static func kind(appleCondition: String) -> (kind: WeatherKind, intensity: Double) {
        let row = table[appleCondition] ?? (.cloudy, 0)
        return (row.0, row.1)
    }

    /// false for a condition this table does not know (a new case in a future SDK).
    public static func isKnown(appleCondition: String) -> Bool { table[appleCondition] != nil }

    public static func shouldRefresh(lastSuccess: Date?, lastFailure: Date?, now: Date) -> Bool {
        if let s = lastSuccess, now.timeIntervalSince(s) < refreshInterval { return false }
        if let f = lastFailure, now.timeIntervalSince(f) < retryAfterFailure { return false }
        return true
    }

    public static func isFresh(_ w: WeatherNow, at now: Date) -> Bool {
        now.timeIntervalSince(w.observedAt) < staleAfter
    }

    /// Snow lies when it snows now, or when enough fell since the last warm hour (and it is not warm now).
    public static func snowOnGround(hours: [WeatherHour], temperatureNow: Double, kindNow: WeatherKind) -> Bool {
        if kindNow == .snow { return true }
        if temperatureNow > thawAbove { return false }
        let lastWarm = hours.filter { $0.temperatureC > thawAbove }.map(\.date).max()
        let since = hours.filter { lastWarm == nil || $0.date > lastWarm! }
        return since.reduce(0) { $0 + $1.snowfallMm } >= snowCoverFromMm
    }

    public static func emoji(_ w: WeatherNow) -> String {
        switch w.kind {
        case .clear: return w.isDaylight ? "☀️" : "🌙"
        case .cloudy: return w.isDaylight && w.cloudCover < 0.7 ? "⛅️" : "☁️"
        case .fog: return "🌫️"
        case .rain: return "🌧️"
        case .thunder: return "⛈️"
        case .snow: return "🌨️"
        }
    }

    /// Whole degrees, never "-0".
    public static func roundedDegrees(_ value: Double) -> Int {
        let r = Int(value.rounded())
        return r == 0 ? 0 : r
    }
}
