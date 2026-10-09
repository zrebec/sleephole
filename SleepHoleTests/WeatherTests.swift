import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
import WeatherKit
@testable import SleepHole

/// A source the tests steer: answers with `result`, counts the questions.
final class FakeWeatherSource: WeatherSource, @unchecked Sendable {
    var result: Result<WeatherNow, Error> = .failure(WeatherSourceError.unavailable)
    var calls = 0
    var name: String { "fake" }
    var lastHourCount: Int { 3 }
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow {
        calls += 1
        return try result.get()
    }
}

@MainActor
struct WeatherStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let city = SkyCity(name: "Bratislava", latitude: 48.1486, longitude: 17.1077)
    let other = SkyCity(name: "Košice", latitude: 48.7164, longitude: 21.2611)    // i18n-ignore

    func suite() -> UserDefaults {
        let name = "weather.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func value(_ temp: Double = 14, at date: Date? = nil) -> WeatherNow {
        WeatherNow(temperatureC: temp, kind: .rain, intensity: 0.6, cloudCover: 1, isDaylight: true,
                   snowOnGround: false, observedAt: date ?? t0)
    }

    func make(_ source: FakeWeatherSource, defaults: UserDefaults? = nil) -> WeatherStore {
        WeatherStore(source: source, defaults: defaults ?? suite())
    }

    @Test func successIsShownAndFailureKeepsItUntilStale() async {
        let src = FakeWeatherSource()
        src.result = .success(value())
        let store = make(src)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        #expect(store.shown(for: city, at: t0, daylight: true)?.temperatureC == 14 && store.lastSuccess == t0 && store.lastError == nil)
        src.result = .failure(WeatherSourceError.unavailable)
        let later = t0 + WeatherRules.refreshInterval
        await store.refreshIfNeeded(city: city, now: later, nightActive: false)
        #expect(store.lastFailure == later && store.lastError?.isEmpty == false)
        #expect(store.shown(for: city, at: later, daylight: true) != nil)                           // the cached value stays
        #expect(store.shown(for: city, at: t0 + WeatherRules.staleAfter, daylight: true) == nil)    // until it is stale
    }

    @Test func nothingIsAskedDuringANightWithoutACityOrInsideTheLimit() async {
        let src = FakeWeatherSource()
        src.result = .success(value())
        let store = make(src)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: true)
        await store.refreshIfNeeded(city: nil, now: t0, nightActive: false)
        #expect(src.calls == 0)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        await store.refreshIfNeeded(city: city, now: t0 + WeatherRules.refreshInterval - 1, nightActive: false)
        #expect(src.calls == 1)
        await store.refreshIfNeeded(city: city, now: t0 + WeatherRules.refreshInterval, nightActive: false)
        #expect(src.calls == 2)
        #expect(store.shown(for: nil, at: t0, daylight: true) == nil)
    }

    @Test func aRetryIsAllowedFiveMinutesAfterAFailure() async {
        let src = FakeWeatherSource()
        let store = make(src)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        await store.refreshIfNeeded(city: city, now: t0 + WeatherRules.retryAfterFailure - 1, nightActive: false)
        #expect(src.calls == 1)
        src.result = .success(value())
        await store.refreshIfNeeded(city: city, now: t0 + WeatherRules.retryAfterFailure, nightActive: false)
        #expect(src.calls == 2 && store.shown(for: city, at: t0 + WeatherRules.retryAfterFailure, daylight: true) != nil)
        #expect(store.lastError == nil)
    }

    @Test func refreshNowIgnoresTheRateLimitButNotTheMissingCity() async {
        let src = FakeWeatherSource()
        src.result = .success(value())
        let store = make(src)
        await store.refreshNow(city: nil, now: t0)
        #expect(src.calls == 0)
        await store.refreshNow(city: city, now: t0)
        await store.refreshNow(city: city, now: t0 + 1)
        #expect(src.calls == 2)
    }

    @Test func aChangedCityDropsTheOldValue() async {
        let src = FakeWeatherSource()
        src.result = .success(value())
        let store = make(src)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        #expect(store.shown(for: other, at: t0, daylight: true) == nil)                 // never another city's weather
        store.sync(city: other)
        #expect(store.shown(for: city, at: t0, daylight: true) == nil && store.lastSuccess == nil)
        await store.refreshIfNeeded(city: other, now: t0 + 1, nightActive: false)   // asks at once, no 30 min wait
        #expect(src.calls == 2)
    }

    @Test func theCacheSurvivesANewStore() async {
        let defaults = suite()
        let src = FakeWeatherSource()
        src.result = .success(value(-3))
        await make(src, defaults: defaults).refreshIfNeeded(city: city, now: t0, nightActive: false)
        let again = make(FakeWeatherSource(), defaults: defaults)
        #expect(again.shown(for: city, at: t0 + 60, daylight: true)?.temperatureC == -3 && again.lastSuccess == t0)
        #expect(again.shown(for: other, at: t0 + 60, daylight: true) == nil)
    }

    @Test func theSimulationOverridesButIsNeverStored() async {
        let defaults = suite()
        let src = FakeWeatherSource()
        src.result = .success(value())
        let store = make(src, defaults: defaults)
        store.simulation = WeatherSimulation(kind: .snow, heavy: false, temperatureC: -5, snowOnGround: true)
        let shown = store.shown(for: city, at: t0, daylight: false)
        #expect(shown?.kind == .snow && shown?.temperatureC == -5 && shown?.isDaylight == false && shown?.snowOnGround == true)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        #expect(src.calls == 0)                                          // a simulation asks nobody
        #expect(make(FakeWeatherSource(), defaults: defaults).simulation == nil)   // never stored
        store.simulation = nil
        #expect(store.activeSimulation == nil)
    }

    @Test func aCachedDaytimeValueFollowsTheSkyAtDisplayTime() async {
        let src = FakeWeatherSource()
        src.result = .success(value())                                   // fetched by day (isDaylight = true)
        let store = make(src)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        #expect(store.shown(for: city, at: t0 + 60, daylight: true)?.isDaylight == true)
        #expect(store.shown(for: city, at: t0 + 60, daylight: false)?.isDaylight == false)
    }

    @Test func launchArgumentsBuildTheSimulation() {
        let sim = WeatherSimulation.from(args: ["x", "-weather", "snow", "-weatherTemp", "-3", "-weatherSnowCover"])
        #expect(sim == WeatherSimulation(kind: .snow, heavy: false, temperatureC: -3, snowOnGround: true))
        #expect(WeatherSimulation.from(args: ["-weather", "heavyRain"]) == WeatherSimulation(kind: .rain, heavy: true))
        #expect(WeatherSimulation.from(args: ["-weather", "lava"]) == nil && WeatherSimulation.from(args: []) == nil)
        let rain = WeatherSimulation(kind: .rain, heavy: true).value(at: t0, isDaylight: true)
        #expect(rain.intensity == 1 && rain.cloudCover == 1)
        let store = WeatherStore(source: NoWeather(), defaults: suite(),
                                 launchSimulation: WeatherSimulation.from(args: ["-weather", "fog"]))
        #expect(store.shown(for: city, at: t0, daylight: true)?.kind == .fog)
        #expect(store.simulation == nil)                                 // one launch only, never stored
    }

    @Test func theWindLaunchArgument() {
        let windy = WeatherSimulation.from(args: ["-weather", "clear", "-weatherWind", "12"])
        #expect(windy?.windMS == 12)
        let value = windy?.value(at: t0, isDaylight: true)
        #expect(value?.windSpeedMS == 12 && value?.windLevel == .windy && value?.windFromDegrees == 270)
        let calm = WeatherSimulation.from(args: ["-weather", "clear"])?.value(at: t0, isDaylight: true)
        #expect(calm?.windSpeedMS == 0 && calm?.windLevel == .calm)
    }

    @Test func windSurvivesTheCacheAndAnOldCacheWithoutItLoads() async throws {
        let defaults = suite()
        let src = FakeWeatherSource()
        var v = value(5)
        v.windSpeedMS = 9.5
        v.windFromDegrees = 240
        src.result = .success(v)
        await make(src, defaults: defaults).refreshIfNeeded(city: city, now: t0, nightActive: false)
        let again = make(FakeWeatherSource(), defaults: defaults)
        let shown = again.shown(for: city, at: t0 + 60, daylight: true)
        #expect(shown?.windSpeedMS == 9.5 && shown?.windFromDegrees == 240 && shown?.windLevel == .windy)

        let old = suite()
        let json = """
        {"weather":{"temperatureC":4,"kind":"rain","intensity":0.6,"cloudCover":1,"isDaylight":true,"snowOnGround":false,"observedAt":\(t0.timeIntervalSinceReferenceDate)},
         "latitude":48.1486,"longitude":17.1077,"lastSuccess":\(t0.timeIntervalSinceReferenceDate)}
        """
        old.set(Data(json.utf8), forKey: WeatherStore.cacheKey)
        let loaded = make(FakeWeatherSource(), defaults: old).shown(for: city, at: t0, daylight: true)
        #expect(loaded?.temperatureC == 4 && loaded?.windSpeedMS == nil && loaded?.windLevel == .calm)
    }

    @Test func sourcesForLaunch() async throws {
        #expect(WeatherSources.forLaunch(args: ["-weather", "rain"], underTest: true) is NoWeather)
        let sim = WeatherSources.forLaunch(args: ["-weather", "snow", "-weatherTemp", "-3", "-weatherSnowCover"], underTest: false)
        let w = try await sim.now(at: city.place, date: t0)
        #expect(w.kind == .snow && w.temperatureC == -3 && w.snowOnGround)
        #if targetEnvironment(simulator)
        #expect(WeatherSources.forLaunch(args: [], underTest: false) is NoWeather)
        #endif
        await #expect(throws: WeatherSourceError.self) { try await NoWeather().now(at: city.place, date: t0) }
    }

    @Test func everyWeatherKitConditionIsInTheTable() {
        for c in WeatherCondition.allCases {
            #expect(WeatherRules.isKnown(appleCondition: c.rawValue), "unmapped WeatherKit condition \(c.rawValue)")
        }
    }

    @Test func theBadgeText() {
        func w(_ t: Double, _ kind: WeatherKind = .rain, daylight: Bool = true) -> WeatherNow {
            WeatherNow(temperatureC: t, kind: kind, intensity: 0.6, cloudCover: 1, isDaylight: daylight,
                       snowOnGround: false, observedAt: t0)
        }
        #expect(WeatherLabel.text(w(13.6), fahrenheit: false) == "14° 🌧️")
        #expect(WeatherLabel.text(w(13.6), fahrenheit: true) == "56° 🌧️")
        #expect(WeatherLabel.text(w(-0.2), fahrenheit: false) == "0° 🌧️")             // never "-0"
        #expect(WeatherLabel.text(w(-12, .snow), fahrenheit: false) == "-12° 🌨️")
        #expect(WeatherLabel.text(w(8, .clear, daylight: false), fahrenheit: false) == "8° 🌙")
        #expect(WeatherLabel.text(w(20, .clear), fahrenheit: false) == "20° ☀️")
        #expect(WeatherLabel.text(w(5, .fog), fahrenheit: false) == "5° 🌫️")
        #expect(WeatherLabel.text(w(18, .thunder), fahrenheit: false) == "18° ⛈️")
        let saved = Lang.current
        defer { Lang.current = saved }
        Lang.current = .en
        #expect(WeatherLabel.accessibility(w(14), fahrenheit: false) == "Rain 14°")
        Lang.current = .sk
        #expect(WeatherLabel.accessibility(w(14), fahrenheit: false) == "Dážď 14°")
        #expect(WeatherKind.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func noCityOrAStaleValueShowsNothing() async {
        let src = FakeWeatherSource()
        src.result = .success(value())
        let store = make(src)
        await store.refreshIfNeeded(city: city, now: t0, nightActive: false)
        #expect(store.shown(for: nil, at: t0, daylight: true) == nil)
        #expect(store.shown(for: city, at: t0 + WeatherRules.staleAfter, daylight: true) == nil)
        #expect(store.shown(for: city, at: t0, daylight: true) != nil)
    }
}

@MainActor
struct WeatherViewsTests {
    let sprites = SpriteLibrary.loadFromBundle()

    func render<V: View>(_ view: V, _ model: AppModel) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test(arguments: AppLanguage.allCases) func theNewViewsRender(language: AppLanguage) async throws {
        let c = try ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                   JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var s = AppSettings()
        s.city = SkyCity(name: "Bratislava", latitude: 48.1486, longitude: 17.1077)
        let name = "weather.views.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = WeatherStore(source: NoWeather(), defaults: defaults)
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: FakeClock(Date()), settings: s,
                         servicesEnabled: false, weather: store, defaults: defaults)
        m.language = language
        render(WeatherTestView(), m)                                    // live, nothing shown
        store.simulation = WeatherSimulation(kind: .snow, heavy: true, temperatureC: -12, snowOnGround: true)
        render(WeatherTestView(), m)                                    // simulated
        store.simulation?.windMS = 16
        render(WeatherTestView(), m)                                    // simulated, with a gale
        render(NavigationStack { HomeView() }, m)                       // title with the weather
        render(WeatherAttribution(), m)
        render(CreditsView(), m)
        render(NavigationStack { Form { SkySection() } }, m)
        await store.refreshNow(city: s.city, now: Date())
        #expect(store.lastError != nil)
        #expect(WeatherAttribution.mark.hasSuffix(" Weather") && WeatherAttribution.legalURL.host == "developer.apple.com")
        #expect(Fmt.degrees(0, fahrenheit: true) == 32 && Fmt.degrees(100, fahrenheit: false) == 100)
    }
}

// MARK: - MET Norway and the fallback

enum MetSample {
    static let json = """
    {"properties":{"timeseries":[
      {"time":"2026-10-07T14:00:00Z","data":{"instant":{"details":{"air_temperature":23.1,"cloud_area_fraction":0.0}},
        "next_1_hours":{"summary":{"symbol_code":"clearsky_day"},"details":{"precipitation_amount":0.0}}}},
      {"time":"2026-10-07T15:00:00Z","data":{"instant":{"details":{"air_temperature":22.5,"cloud_area_fraction":82.4}},
        "next_1_hours":{"summary":{"symbol_code":"heavyrainshowers_night"},"details":{"precipitation_amount":3.1}}}}
    ]}}
    """
}

final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URLRequest] = []
    func add(_ r: URLRequest) { lock.lock(); items.append(r); lock.unlock() }
    var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return items }
}

final class FakeClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ d: Date) { value = d }
    var now: Date { get { lock.lock(); defer { lock.unlock() }; return value } set { lock.lock(); value = newValue; lock.unlock() } }
}

struct MetNorwaySourceTests {
    let place = GeoPoint(latitude: 48.1486, longitude: 17.1077)
    let t0 = ISO8601DateFormatter().date(from: "2026-10-07T15:20:00Z")!
    let body = Data(MetSample.json.utf8)

    func response(_ code: Int, expires: String? = nil) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let expires { headers["Expires"] = expires }
        return HTTPURLResponse(url: URL(string: "https://api.met.no/x")!, statusCode: code, httpVersion: nil, headerFields: headers)!
    }

    @Test func answersAndSendsTheRightRequest() async throws {
        let log = RequestLog()
        let source = MetNorwaySource(transport: { r in log.add(r); return (Data(MetSample.json.utf8), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) },
                                     clock: { Date() })
        let w = try await source.now(at: place, date: t0)
        #expect(w.temperatureC == 22.5 && w.kind == .rain)
        #expect(source.lastProvider == .metNorway && source.name == "MET Norway" && source.lastHourCount == 0)
        let request = try #require(log.all.first)
        #expect(request.url?.absoluteString == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=48.15&lon=17.11")
        let agent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(agent.hasPrefix("SleepHole/") && agent.hasSuffix("github.com/zrebec/sleephole") && !agent.contains("@"))
    }

    @Test func respectsExpires() async throws {
        let log = RequestLog()
        let clock = FakeClockBox(Date(timeIntervalSince1970: 1_800_000_000))        // Fri, 15 Jan 2027 08:00:00 GMT
        let body = self.body
        let source = MetNorwaySource(transport: { r in
            log.add(r)
            return (body, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil,
                                          headerFields: ["Expires": "Fri, 15 Jan 2027 08:30:00 GMT"])!)
        }, clock: { clock.now })
        _ = try await source.now(at: place, date: t0)
        clock.now = clock.now.addingTimeInterval(29 * 60)
        let again = try await source.now(at: place, date: t0)
        #expect(log.all.count == 1 && again.temperatureC == 22.5)                 // answered from the remembered body
        clock.now = clock.now.addingTimeInterval(2 * 60)
        _ = try await source.now(at: place, date: t0)
        #expect(log.all.count == 2)                                               // Expires has passed: asks again
        _ = try await source.now(at: GeoPoint(latitude: 50, longitude: 14), date: t0)
        #expect(log.all.count == 3)                                               // another place is another URL
    }

    @Test(arguments: [403, 429, 500]) func aBadStatusNamesTheCode(code: Int) async {
        let r = response(code)
        let source = MetNorwaySource(transport: { _ in (Data(), r) }, clock: { Date() })
        do {
            _ = try await source.now(at: place, date: t0)
            Issue.record("should throw")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            #expect(text.contains("\(code)"))
        }
    }

    @Test func aTransportErrorPassesThrough() async {
        struct Boom: Error {}
        let source = MetNorwaySource(transport: { _ in throw Boom() }, clock: { Date() })
        await #expect(throws: Boom.self) { try await source.now(at: place, date: t0) }
    }
}

struct FallbackWeatherTests {
    let place = GeoPoint(latitude: 48.1486, longitude: 17.1077)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    final class Stub: WeatherSource, @unchecked Sendable {
        let provider: WeatherProvider
        let result: Result<WeatherNow, Error>
        init(_ provider: WeatherProvider, _ result: Result<WeatherNow, Error>) { self.provider = provider; self.result = result }
        var name: String { provider.rawValue }
        var lastHourCount: Int { 0 }
        var lastProvider: WeatherProvider { provider }
        func now(at place: GeoPoint, date: Date) async throws -> WeatherNow { try result.get() }
    }

    struct Refused: LocalizedError { var errorDescription: String? { "token refused" } }

    func value(_ t: Double) -> WeatherNow {
        WeatherNow(temperatureC: t, kind: .clear, intensity: 0, cloudCover: 0, isDaylight: true, snowOnGround: false, observedAt: t0)
    }

    @Test func primaryAnswers() async throws {
        let f = FallbackWeather(primary: Stub(.apple, .success(value(1))), secondary: Stub(.metNorway, .success(value(2))))
        #expect(try await f.now(at: place, date: t0).temperatureC == 1)
        #expect(f.lastProvider == .apple && f.lastNote == nil && f.name == "apple → metNorway")
    }

    @Test func secondaryAnswersAndTheNoteKeepsThePrimarysError() async throws {
        let f = FallbackWeather(primary: Stub(.apple, .failure(Refused())), secondary: Stub(.metNorway, .success(value(2))))
        #expect(try await f.now(at: place, date: t0).temperatureC == 2)
        #expect(f.lastProvider == .metNorway)
        #expect(f.lastNote?.contains("token refused") == true)
    }

    @Test func bothFailAndTheErrorNamesBoth() async {
        struct Down: LocalizedError { var errorDescription: String? { "HTTP 503" } }
        let f = FallbackWeather(primary: Stub(.apple, .failure(Refused())), secondary: Stub(.metNorway, .failure(Down())))
        do {
            _ = try await f.now(at: place, date: t0)
            Issue.record("should throw")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            #expect(text.contains("token refused") && text.contains("HTTP 503"))
        }
    }
}

@MainActor
struct WeatherProviderStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let city = SkyCity(name: "Bratislava", latitude: 48.1486, longitude: 17.1077)

    func suite() -> UserDefaults {
        let name = "weather.provider.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func theProviderSurvivesARelaunch() async {
        let defaults = suite()
        let fallback = FallbackWeather(primary: NoWeather(),
                                       secondary: FallbackWeatherTests.Stub(.metNorway, .success(
                                           WeatherNow(temperatureC: 9, kind: .fog, intensity: 0, cloudCover: 1, isDaylight: true,
                                                      snowOnGround: false, observedAt: t0))))
        let store = WeatherStore(source: fallback, defaults: defaults)
        await store.refreshNow(city: city, now: t0)
        #expect(store.provider == .metNorway && store.note?.isEmpty == false && store.shownProvider == .metNorway)
        let again = WeatherStore(source: NoWeather(), defaults: defaults)
        #expect(again.provider == .metNorway && again.shown(for: city, at: t0 + 60, daylight: true)?.temperatureC == 9)
    }

    @Test func anOldCacheWithoutTheProviderIsApple() throws {
        let defaults = suite()
        let json = """
        {"weather":{"temperatureC":4,"kind":"rain","intensity":0.6,"cloudCover":1,"isDaylight":true,"snowOnGround":false,"observedAt":\(t0.timeIntervalSinceReferenceDate)},
         "latitude":48.1486,"longitude":17.1077,"lastSuccess":\(t0.timeIntervalSinceReferenceDate)}
        """
        defaults.set(Data(json.utf8), forKey: WeatherStore.cacheKey)
        let store = WeatherStore(source: NoWeather(), defaults: defaults)
        #expect(store.provider == .apple && store.shown(for: city, at: t0, daylight: true)?.temperatureC == 4)
    }

    @Test func aSimulationReportsSimulated() {
        let store = WeatherStore(source: NoWeather(), defaults: suite())
        store.simulation = WeatherSimulation(kind: .rain)
        #expect(store.shownProvider == .simulated)
    }

    @Test func forLaunchKnowsTheMetArgument() {
        #expect(WeatherSources.forLaunch(args: ["-weatherSource", "met"], underTest: false) is MetNorwaySource)
        #expect(WeatherSources.forLaunch(args: ["-weatherSource", "met"], underTest: true) is NoWeather)
        #expect(WeatherSources.forLaunch(args: ["-weatherSource", "met", "-weather", "rain"], underTest: false) is SimulatedWeather)
        #expect(!(WeatherSources.forLaunch(args: ["-weatherSource", "other"], underTest: false) is MetNorwaySource))
    }
}

@MainActor
struct WeatherCreditTests {
    @Test(arguments: AppLanguage.allCases, WeatherProvider.allCases)
    func theCreditRenders(language: AppLanguage, provider: WeatherProvider) {
        for dark in [false, true] { renderCredit(language, provider, dark: dark) }
    }

    func renderCredit(_ language: AppLanguage, _ provider: WeatherProvider, dark: Bool) {
        let saved = Lang.current
        defer { Lang.current = saved }
        Lang.current = language
        let host = UIHostingController(rootView: WeatherAttribution(provider: provider))
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 200))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.05)
        #expect(host.view.bounds.width > 0)
        window.isHidden = true
        #expect(WeatherAttribution.metLicenceURL.host == "www.met.no")
    }
}
