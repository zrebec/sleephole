import Foundation

/// Who gave the weather value that is shown (the credit and the Developer screen follow it).
public enum WeatherProvider: String, Codable, Sendable, CaseIterable { case apple, metNorway, simulated }

/// MET Norway (api.met.no, locationforecast 2.0 compact): the symbol rule, the request and the parser. Pure.
public enum MetNorway {
    /// The 41 base symbol names (MET's own spellings, incl. the two "lightss…").
    public static let symbols: [String] = [
        "clearsky", "fair", "partlycloudy", "cloudy", "fog",
        "lightrain", "rain", "heavyrain", "lightrainshowers", "rainshowers", "heavyrainshowers",
        "lightsleet", "sleet", "heavysleet", "lightsleetshowers", "sleetshowers", "heavysleetshowers",
        "lightsnow", "snow", "heavysnow", "lightsnowshowers", "snowshowers", "heavysnowshowers",
        "lightrainandthunder", "rainandthunder", "heavyrainandthunder",
        "lightrainshowersandthunder", "rainshowersandthunder", "heavyrainshowersandthunder",
        "lightsleetandthunder", "sleetandthunder", "heavysleetandthunder",
        "lightssleetshowersandthunder", "sleetshowersandthunder", "heavysleetshowersandthunder",
        "lightsnowandthunder", "snowandthunder", "heavysnowandthunder",
        "lightssnowshowersandthunder", "snowshowersandthunder", "heavysnowshowersandthunder",
    ]

    /// The symbol without its `_day` / `_night` / `_polartwilight` suffix.
    public static func baseName(_ symbol: String) -> String {
        for suffix in ["_day", "_night", "_polartwilight"] where symbol.hasSuffix(suffix) {
            return String(symbol.dropLast(suffix.count))
        }
        return symbol
    }

    public static func isKnown(metSymbol symbol: String) -> Bool { symbols.contains(baseName(symbol)) }

    /// `_night` is night, everything else (day, polar twilight, no suffix) counts as day.
    public static func isDay(metSymbol symbol: String) -> Bool { !symbol.hasSuffix("_night") }

    public static func kind(metSymbol symbol: String) -> (kind: WeatherKind, intensity: Double) {
        let base = baseName(symbol)
        guard symbols.contains(base) else { return (.cloudy, 0) }
        func level(light: Double, plain: Double, heavy: Double) -> Double {
            base.hasPrefix("light") ? light : base.hasPrefix("heavy") ? heavy : plain
        }
        if base.contains("thunder") { return (.thunder, level(light: 0.6, plain: 0.8, heavy: 1)) }
        if base.contains("snow") { return (.snow, level(light: 0.25, plain: 0.6, heavy: 1)) }
        if base.contains("sleet") { return (.snow, 0.5) }
        if base.contains("rain") { return (.rain, level(light: 0.25, plain: 0.6, heavy: 1)) }
        if base == "fog" { return (.fog, 0) }
        if base == "cloudy" || base == "partlycloudy" { return (.cloudy, 0) }
        return (.clear, 0)
    }

    /// The forecast request for a place: at most 2 decimals (about 1 km), as MET asks for as few as are needed.
    public static func requestURL(for place: GeoPoint) -> URL {
        func two(_ v: Double) -> String {
            let r = (v * 100).rounded() / 100
            return String(format: "%.2f", r == 0 ? 0 : r)
        }
        return URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(two(place.latitude))&lon=\(two(place.longitude))")!
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    private struct Response: Decodable {
        struct Properties: Decodable { var timeseries: [Entry] }
        struct Entry: Decodable {
            var time: String
            var data: DataPart
        }
        struct DataPart: Decodable {
            var instant: Instant
            var next_1_hours: Period?
            var next_6_hours: Period?
        }
        struct Instant: Decodable { var details: Details }
        struct Details: Decodable {
            var air_temperature: Double?
            var cloud_area_fraction: Double?
            var wind_speed: Double?
            var wind_from_direction: Double?
        }
        struct Period: Decodable { var summary: Summary? }
        struct Summary: Decodable { var symbol_code: String }
        var properties: Properties
    }

    private static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }

    /// The value for `now` from a response body: the last entry not after `now` (else the first).
    public static func parse(_ data: Data, now: Date) throws -> WeatherNow {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw ParseError(description: "MET Norway answer is not readable (\(error.localizedDescription))") }
        let dated = response.properties.timeseries.compactMap { e in date(e.time).map { ($0, e) } }
        guard let first = dated.first else { throw ParseError(description: "MET Norway answer has no forecast entries") }
        let entry = (dated.last { $0.0 <= now } ?? first).1
        guard let temperature = entry.data.instant.details.air_temperature else {
            throw ParseError(description: "MET Norway answer has no temperature")
        }
        let details = entry.data.instant.details
        let cover = min(max((details.cloud_area_fraction ?? 0) / 100, 0), 1)
        let symbol = entry.data.next_1_hours?.summary?.symbol_code ?? entry.data.next_6_hours?.summary?.symbol_code
        let kind: WeatherKind
        let intensity: Double
        let daylight: Bool
        if let symbol {
            (kind, intensity) = Self.kind(metSymbol: symbol)
            daylight = isDay(metSymbol: symbol)
        } else {
            (kind, intensity) = cover > 0.5 ? (.cloudy, 0) : (.clear, 0)
            daylight = true
        }
        return WeatherNow(
            temperatureC: temperature, kind: kind, intensity: intensity, cloudCover: cover, isDaylight: daylight,
            snowOnGround: WeatherRules.snowOnGround(hours: [], temperatureNow: temperature, kindNow: kind),
            observedAt: now,
            windSpeedMS: details.wind_speed.flatMap { $0 >= 0 ? $0 : nil },
            windFromDegrees: details.wind_from_direction)
    }
}
