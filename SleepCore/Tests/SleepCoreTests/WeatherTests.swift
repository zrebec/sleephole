import Foundation
import Testing
@testable import SleepCore

@Suite struct WeatherTests {
    static let table: [(String, WeatherKind, Double)] = [
        ("clear", .clear, 0), ("mostlyClear", .clear, 0), ("hot", .clear, 0), ("frigid", .clear, 0),
        ("breezy", .clear, 0), ("windy", .clear, 0),
        ("partlyCloudy", .cloudy, 0), ("mostlyCloudy", .cloudy, 0), ("cloudy", .cloudy, 0),
        ("foggy", .fog, 0), ("haze", .fog, 0), ("smoky", .fog, 0), ("blowingDust", .fog, 0),
        ("drizzle", .rain, 0.25), ("freezingDrizzle", .rain, 0.25), ("sunShowers", .rain, 0.3),
        ("rain", .rain, 0.6), ("freezingRain", .rain, 0.6), ("hail", .rain, 0.8), ("heavyRain", .rain, 1),
        ("tropicalStorm", .rain, 1), ("hurricane", .rain, 1),
        ("isolatedThunderstorms", .thunder, 0.6), ("scatteredThunderstorms", .thunder, 0.7),
        ("thunderstorms", .thunder, 0.9), ("strongStorms", .thunder, 1),
        ("flurries", .snow, 0.25), ("sunFlurries", .snow, 0.25), ("sleet", .snow, 0.5), ("wintryMix", .snow, 0.5),
        ("snow", .snow, 0.6), ("blowingSnow", .snow, 0.7), ("heavySnow", .snow, 1), ("blizzard", .snow, 1),
    ]

    @Test(arguments: table) func everyRowOfTheTable(row: (String, WeatherKind, Double)) {
        let r = WeatherRules.kind(appleCondition: row.0)
        #expect(r.kind == row.1 && r.intensity == row.2)
        #expect(WeatherRules.isKnown(appleCondition: row.0))
    }

    @Test func anUnknownConditionIsCloudy() {
        let r = WeatherRules.kind(appleCondition: "meteorShower")
        #expect(r.kind == .cloudy && r.intensity == 0)
        #expect(!WeatherRules.isKnown(appleCondition: "meteorShower"))
    }

    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func refreshRules() {
        let i = WeatherRules.refreshInterval, r = WeatherRules.retryAfterFailure
        #expect(WeatherRules.shouldRefresh(lastSuccess: nil, lastFailure: nil, now: t0))
        #expect(!WeatherRules.shouldRefresh(lastSuccess: t0, lastFailure: nil, now: t0 + i - 1))
        #expect(WeatherRules.shouldRefresh(lastSuccess: t0, lastFailure: nil, now: t0 + i))
        #expect(!WeatherRules.shouldRefresh(lastSuccess: nil, lastFailure: t0, now: t0 + r - 1))
        #expect(WeatherRules.shouldRefresh(lastSuccess: nil, lastFailure: t0, now: t0 + r))
        // a failure after an old success: the retry interval applies, the success is long ago
        #expect(!WeatherRules.shouldRefresh(lastSuccess: t0 - 3600, lastFailure: t0, now: t0 + 60))
        #expect(WeatherRules.shouldRefresh(lastSuccess: t0 - 3600, lastFailure: t0, now: t0 + r))
    }

    func now(_ kind: WeatherKind = .clear, daylight: Bool = true, cover: Double = 0, observed: Date? = nil) -> WeatherNow {
        WeatherNow(temperatureC: 10, kind: kind, intensity: 0, cloudCover: cover, isDaylight: daylight,
                   snowOnGround: false, observedAt: observed ?? t0)
    }

    @Test func windLevelBoundaries() {
        let rows: [(Double?, WindLevel)] = [
            (nil, .calm), (0, .calm), (2.99, .calm), (3, .breeze), (7.99, .breeze), (8, .windy),
            (13.99, .windy), (14, .gale), (40, .gale),
        ]
        for (speed, level) in rows { #expect(WeatherRules.windLevel(speedMS: speed) == level, "\(String(describing: speed))") }
        #expect(WindLevel.calm < .breeze && WindLevel.windy < .gale && WindLevel.allCases.count == 4)
        var w = now()
        #expect(w.windLevel == .calm)
        w.windSpeedMS = 9
        #expect(w.windLevel == .windy)
    }

    @Test func windDirectionLeftOrRight() {
        #expect(WeatherRules.windBlowsRight(fromDegrees: 270))
        #expect(WeatherRules.windBlowsRight(fromDegrees: 181) && WeatherRules.windBlowsRight(fromDegrees: 359.9))
        #expect(!WeatherRules.windBlowsRight(fromDegrees: 90))
        #expect(!WeatherRules.windBlowsRight(fromDegrees: 0) && !WeatherRules.windBlowsRight(fromDegrees: 180))
        #expect(!WeatherRules.windBlowsRight(fromDegrees: 360))
        #expect(WeatherRules.windBlowsRight(fromDegrees: -90))
        #expect(WeatherRules.windBlowsRight(fromDegrees: nil))
    }

    @Test func windCodableIsBackwardCompatible() throws {
        let old = """
        {"temperatureC":4,"kind":"rain","intensity":0.6,"cloudCover":1,"isDaylight":true,"snowOnGround":false,"observedAt":0}
        """
        let decoded = try JSONDecoder().decode(WeatherNow.self, from: Data(old.utf8))
        #expect(decoded.windSpeedMS == nil && decoded.windFromDegrees == nil)
        var w = now()
        w.windSpeedMS = 6.5
        w.windFromDegrees = 300
        let back = try JSONDecoder().decode(WeatherNow.self, from: JSONEncoder().encode(w))
        #expect(back == w && back.windSpeedMS == 6.5 && back.windFromDegrees == 300)
    }

    @Test func freshnessEdge() {
        let w = now()
        #expect(WeatherRules.isFresh(w, at: t0 + WeatherRules.staleAfter - 1))
        #expect(!WeatherRules.isFresh(w, at: t0 + WeatherRules.staleAfter))
    }

    func hour(_ hoursAgo: Double, _ temp: Double, _ snow: Double) -> WeatherHour {
        WeatherHour(date: t0 - hoursAgo * 3600, temperatureC: temp, snowfallMm: snow)
    }

    @Test func snowRule() {
        // snowing now
        #expect(WeatherRules.snowOnGround(hours: [], temperatureNow: -1, kindNow: .snow))
        #expect(WeatherRules.snowOnGround(hours: [], temperatureNow: 5, kindNow: .snow))
        // no hours: only "it snows now" counts
        #expect(!WeatherRules.snowOnGround(hours: [], temperatureNow: -5, kindNow: .clear))
        // snow two days ago, then a thaw: gone
        let thaw = [hour(48, -2, 8), hour(40, -1, 3), hour(24, 6, 0), hour(10, 1, 0)]
        #expect(!WeatherRules.snowOnGround(hours: thaw, temperatureNow: -1, kindNow: .clear))
        // snow last night and frost since: lies
        let frost = [hour(30, 5, 0), hour(12, -1, 3), hour(11, -2, 3), hour(2, -3, 0)]
        #expect(WeatherRules.snowOnGround(hours: frost, temperatureNow: -3, kindNow: .cloudy))
        // too little snow
        let little = [hour(12, -1, 2), hour(11, -2, 2.9)]
        #expect(!WeatherRules.snowOnGround(hours: little, temperatureNow: -3, kindNow: .clear))
        // exactly the limit
        #expect(WeatherRules.snowOnGround(hours: [hour(5, -1, 5)], temperatureNow: 0, kindNow: .clear))
        // warm now
        #expect(!WeatherRules.snowOnGround(hours: frost, temperatureNow: 2.5, kindNow: .clear))
        // exactly thawAbove is not warm
        #expect(WeatherRules.snowOnGround(hours: frost, temperatureNow: 2.0, kindNow: .clear))
        // no warm hour at all: all hours count
        #expect(WeatherRules.snowOnGround(hours: [hour(40, -4, 3), hour(3, -4, 2)], temperatureNow: -4, kindNow: .clear))
    }

    @Test func emojis() {
        #expect(WeatherRules.emoji(now(.clear, daylight: true)) == "☀️")
        #expect(WeatherRules.emoji(now(.clear, daylight: false)) == "🌙")
        #expect(WeatherRules.emoji(now(.cloudy, daylight: true, cover: 0.69)) == "⛅️")
        #expect(WeatherRules.emoji(now(.cloudy, daylight: true, cover: 0.7)) == "☁️")
        #expect(WeatherRules.emoji(now(.cloudy, daylight: false, cover: 0.2)) == "☁️")
        #expect(WeatherRules.emoji(now(.fog)) == "🌫️")
        #expect(WeatherRules.emoji(now(.rain)) == "🌧️")
        #expect(WeatherRules.emoji(now(.thunder)) == "⛈️")
        #expect(WeatherRules.emoji(now(.snow, daylight: false)) == "🌨️")
    }

    @Test func rounding() {
        #expect(WeatherRules.roundedDegrees(-0.4) == 0)
        #expect(WeatherRules.roundedDegrees(-0.6) == -1)
        #expect(WeatherRules.roundedDegrees(13.5) == 14)
        #expect(WeatherRules.roundedDegrees(-12.2) == -12)
    }

    @Test func weatherNowRoundTripsThroughJSON() throws {
        let w = now(.snow)
        let back = try JSONDecoder().decode(WeatherNow.self, from: JSONEncoder().encode(w))
        #expect(back == w)
    }
}
