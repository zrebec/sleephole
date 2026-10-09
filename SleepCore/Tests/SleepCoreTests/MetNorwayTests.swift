import Foundation
import Testing
@testable import SleepCore

struct MetNorwayTests {
    static let sample = """
    {"type":"Feature","geometry":{"type":"Point","coordinates":[17.11,48.15,150]},
     "properties":{"meta":{"updated_at":"2026-10-07T13:40:00Z"},"timeseries":[
      {"time":"2026-10-07T14:00:00Z","data":{"instant":{"details":{"air_pressure_at_sea_level":1013.3,"air_temperature":23.1,"cloud_area_fraction":0.0,"wind_speed":5.8}},
        "next_12_hours":{"summary":{"symbol_code":"fair_night"},"details":{}},
        "next_1_hours":{"summary":{"symbol_code":"clearsky_day"},"details":{"precipitation_amount":0.0}},
        "next_6_hours":{"summary":{"symbol_code":"fair_night"},"details":{"precipitation_amount":0.0}}}},
      {"time":"2026-10-07T15:00:00Z","data":{"instant":{"details":{"air_temperature":22.5,"cloud_area_fraction":82.4}},
        "next_1_hours":{"summary":{"symbol_code":"heavyrainshowers_night"},"details":{"precipitation_amount":3.1}},
        "next_6_hours":{"summary":{"symbol_code":"rain"},"details":{}}}},
      {"time":"2026-10-07T16:00:00Z","data":{"instant":{"details":{"air_temperature":-1.2,"cloud_area_fraction":100.0}},
        "next_1_hours":{"summary":{"symbol_code":"snow"},"details":{"precipitation_amount":1.0}}}},
      {"time":"2026-10-10T06:00:00Z","data":{"instant":{"details":{"air_temperature":8.6,"cloud_area_fraction":56.2}},
        "next_6_hours":{"summary":{"symbol_code":"fair_day"},"details":{}},
        "next_12_hours":{"summary":{"symbol_code":"cloudy"},"details":{}}}}
     ]}}
    """

    func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    var data: Data { Self.sample.data(using: .utf8)! }

    @Test func allFortyOneNamesWithAndWithoutSuffix() {
        #expect(MetNorway.symbols.count == 41)
        for base in MetNorway.symbols {
            let plain = MetNorway.kind(metSymbol: base)
            #expect(MetNorway.isKnown(metSymbol: base))
            #expect(MetNorway.isDay(metSymbol: base))
            let expectKind: WeatherKind
            let expectIntensity: Double
            let light = base.hasPrefix("light"), heavy = base.hasPrefix("heavy")
            if base.contains("thunder") { expectKind = .thunder; expectIntensity = light ? 0.6 : heavy ? 1 : 0.8 }
            else if base.contains("snow") { expectKind = .snow; expectIntensity = light ? 0.25 : heavy ? 1 : 0.6 }
            else if base.contains("sleet") { expectKind = .snow; expectIntensity = 0.5 }
            else if base.contains("rain") { expectKind = .rain; expectIntensity = light ? 0.25 : heavy ? 1 : 0.6 }
            else if base == "fog" { expectKind = .fog; expectIntensity = 0 }
            else if base.contains("cloudy") { expectKind = .cloudy; expectIntensity = 0 }
            else { expectKind = .clear; expectIntensity = 0 }
            #expect(plain.kind == expectKind && plain.intensity == expectIntensity, "\(base)")
            for suffix in ["_day", "_night", "_polartwilight"] {
                let s = base + suffix
                let r = MetNorway.kind(metSymbol: s)
                #expect(r.kind == plain.kind && r.intensity == plain.intensity, "\(s)")
                #expect(MetNorway.isKnown(metSymbol: s))
                #expect(MetNorway.isDay(metSymbol: s) == (suffix != "_night"))
            }
        }
    }

    @Test func spotChecks() {
        #expect(MetNorway.kind(metSymbol: "clearsky_day") == (.clear, 0))
        #expect(MetNorway.kind(metSymbol: "partlycloudy_night") == (.cloudy, 0))
        #expect(MetNorway.kind(metSymbol: "lightssnowshowersandthunder_day") == (.thunder, 0.6))
        #expect(MetNorway.kind(metSymbol: "heavysleet") == (.snow, 0.5))
    }

    @Test func anUnknownCode() {
        #expect(!MetNorway.isKnown(metSymbol: "volcano_day"))
        #expect(MetNorway.kind(metSymbol: "volcano_day") == (.cloudy, 0))
        #expect(MetNorway.kind(metSymbol: "") == (.cloudy, 0))
    }

    @Test func theRequestRoundsToTwoDecimals() {
        #expect(MetNorway.requestURL(for: GeoPoint(latitude: 48.1486, longitude: 17.1077)).absoluteString
                == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=48.15&lon=17.11")
        #expect(MetNorway.requestURL(for: GeoPoint(latitude: -33.8688, longitude: -70.6693)).absoluteString
                == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=-33.87&lon=-70.67")
        #expect(MetNorway.requestURL(for: GeoPoint(latitude: -0.001, longitude: 5)).absoluteString
                == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=0.00&lon=5.00")
    }

    @Test func parserPicksTheLastEntryNotAfterNow() throws {
        let between = at("2026-10-07T15:30:00Z")
        let w = try MetNorway.parse(data, now: between)
        #expect(w.temperatureC == 22.5 && w.kind == .rain && w.intensity == 1)
        #expect(abs(w.cloudCover - 0.824) < 1e-9 && !w.isDaylight && !w.snowOnGround && w.observedAt == between)
        let exact = try MetNorway.parse(data, now: at("2026-10-07T14:00:00Z"))
        #expect(exact.temperatureC == 23.1 && exact.kind == .clear && exact.isDaylight)
    }

    @Test func nowBeforeTheFirstEntryUsesTheFirst() throws {
        let w = try MetNorway.parse(data, now: at("2026-10-07T10:00:00Z"))
        #expect(w.temperatureC == 23.1 && w.kind == .clear && w.cloudCover == 0)
    }

    @Test func snowingMeansSnowLies() throws {
        let w = try MetNorway.parse(data, now: at("2026-10-07T16:10:00Z"))
        #expect(w.kind == .snow && w.intensity == 0.6 && w.snowOnGround && w.temperatureC == -1.2)
    }

    @Test func anEntryWithoutNextOneHourFallsBackToSixHours() throws {
        let w = try MetNorway.parse(data, now: at("2026-10-10T07:00:00Z"))
        #expect(w.kind == .clear && w.isDaylight && w.temperatureC == 8.6)
    }

    @Test func noSymbolAtAllFallsBackToCloudCover() throws {
        let cloudy = #"{"properties":{"timeseries":[{"time":"2026-10-07T14:00:00Z","data":{"instant":{"details":{"air_temperature":5,"cloud_area_fraction":80}}}}]}}"#
        let clear = #"{"properties":{"timeseries":[{"time":"2026-10-07T14:00:00Z","data":{"instant":{"details":{"air_temperature":5,"cloud_area_fraction":20}}}}]}}"#
        #expect(try MetNorway.parse(Data(cloudy.utf8), now: at("2026-10-07T14:30:00Z")).kind == .cloudy)
        #expect(try MetNorway.parse(Data(clear.utf8), now: at("2026-10-07T14:30:00Z")).kind == .clear)
    }

    @Test func malformedDataThrowsAReadableError() {
        for bad in ["not json", "{}", #"{"properties":{"timeseries":[]}}"#,
                    #"{"properties":{"timeseries":[{"time":"2026-10-07T14:00:00Z","data":{"instant":{"details":{}}}}]}}"#] {
            do {
                _ = try MetNorway.parse(Data(bad.utf8), now: Date())
                Issue.record("should have thrown for \(bad)")
            } catch {
                #expect(String(describing: error).contains("MET Norway"))
            }
        }
    }

    @Test func windFieldsAreParsedOrNil() throws {
        func body(_ details: String) -> Data {
            Data(#"{"properties":{"timeseries":[{"time":"2026-10-07T14:00:00Z","data":{"instant":{"details":{\#(details)}}}}]}}"#.utf8)
        }
        let now = at("2026-10-07T14:30:00Z")
        let with = try MetNorway.parse(body(#""air_temperature":5,"wind_speed":7.5,"wind_from_direction":250.5"#), now: now)
        #expect(with.windSpeedMS == 7.5 && with.windFromDegrees == 250.5)
        let without = try MetNorway.parse(body(#""air_temperature":5"#), now: now)
        #expect(without.windSpeedMS == nil && without.windFromDegrees == nil)
        let negative = try MetNorway.parse(body(#""air_temperature":5,"wind_speed":-1,"wind_from_direction":90"#), now: now)
        #expect(negative.windSpeedMS == nil && negative.windFromDegrees == 90)
        #expect(try MetNorway.parse(data, now: at("2026-10-07T14:00:00Z")).windSpeedMS == 5.8)
    }

    @Test func providerCodable() throws {
        let data = try JSONEncoder().encode(WeatherProvider.metNorway)
        #expect(String(decoding: data, as: UTF8.self) == "\"metNorway\"")
        #expect(WeatherProvider.allCases.count == 3)
    }
}
