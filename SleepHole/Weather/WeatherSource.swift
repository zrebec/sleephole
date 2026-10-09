import CoreLocation
import Foundation
import SleepCore
import WeatherKit
import os

// The weather over the owner's city (plan §10 TOWN-W). The SOURCE is replaceable: anything that can answer "what is
// it like at this place now" as a `WeatherNow` – Apple WeatherKit today, MET Norway / Open-Meteo later.

protocol WeatherSource: Sendable {
    /// A short name for Settings → Developer → Weather test.
    var name: String { get }
    /// How many past hourly values the last answer carried (diagnostics; 0 when none or not applicable).
    var lastHourCount: Int { get }
    /// Which provider gave the last answer (the credit and the Weather test follow it).
    var lastProvider: WeatherProvider { get }
    /// A diagnostic remark about the last answer, e.g. "Apple WeatherKit failed: …"; nil when there is none.
    var lastNote: String? { get }
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow
}

extension WeatherSource {
    var lastProvider: WeatherProvider { .apple }
    var lastNote: String? { nil }
}

enum WeatherSourceError: LocalizedError {
    case unavailable

    var errorDescription: String? { "No weather source on this build (simulator, tests)." }
}

// MARK: - stand-ins

/// Tests, screenshots and the simulator by default: never a value (no network, nothing to provision).
struct NoWeather: WeatherSource {
    var name: String { "none" }
    var lastHourCount: Int { 0 }
    var lastProvider: WeatherProvider { .simulated }
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow { throw WeatherSourceError.unavailable }
}

/// What a simulation (launch arguments or the Developer screen) pretends the weather is.
struct WeatherSimulation: Codable, Equatable {
    var kind: WeatherKind
    var heavy: Bool
    var temperatureC: Double
    var snowOnGround: Bool
    /// m/s, from the west. Never persisted (a simulation lives in memory only), so no decoding concern.
    var windMS: Double

    init(kind: WeatherKind, heavy: Bool = false, temperatureC: Double = 12, snowOnGround: Bool = false,
         windMS: Double = 0) {
        self.kind = kind
        self.heavy = heavy
        self.temperatureC = temperatureC
        self.snowOnGround = snowOnGround
        self.windMS = windMS
    }

    /// The value to show at `date`; `isDaylight` comes from the sky (`LivingSky`).
    func value(at date: Date, isDaylight: Bool) -> WeatherNow {
        let intensity: Double
        switch kind {
        case .rain, .thunder, .snow: intensity = heavy ? 1 : 0.6
        case .clear, .cloudy, .fog: intensity = 0
        }
        let cover: Double
        switch kind {
        case .clear: cover = 0.05
        case .cloudy: cover = 0.6
        case .fog: cover = 0.9
        case .rain, .thunder, .snow: cover = 1
        }
        return WeatherNow(temperatureC: temperatureC, kind: kind, intensity: intensity, cloudCover: cover,
                          isDaylight: isDaylight, snowOnGround: snowOnGround || kind == .snow, observedAt: date,
                          windSpeedMS: windMS, windFromDegrees: 270)
    }

    /// `-weather clear|cloudy|fog|rain|heavyRain|thunder|snow`, `-weatherTemp 14`, `-weatherSnowCover`,
    /// `-weatherWind 12` (m/s, from the west; default 0); nil without `-weather`.
    static func from(args: [String]) -> WeatherSimulation? {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        guard let word = value("-weather") else { return nil }
        let heavy = word == "heavyRain"
        guard let kind = WeatherKind(rawValue: heavy ? "rain" : word) else { return nil }
        return WeatherSimulation(kind: kind, heavy: heavy, temperatureC: value("-weatherTemp").flatMap(Double.init) ?? 12,
                                 snowOnGround: args.contains("-weatherSnowCover"),
                                 windMS: value("-weatherWind").flatMap(Double.init) ?? 0)
    }
}

/// A fixed value as a source (launch arguments `-weather …`).
struct SimulatedWeather: WeatherSource {
    let simulation: WeatherSimulation
    /// Day or night at the given moment.
    let isDaylight: @Sendable (Date) -> Bool

    var name: String { "simulated" }
    var lastHourCount: Int { 0 }
    var lastProvider: WeatherProvider { .simulated }
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow {
        simulation.value(at: date, isDaylight: isDaylight(date))
    }
}

// MARK: - the real thing (Apple WeatherKit)

final class WeatherKitSource: WeatherSource {
    private let hourCount = OSAllocatedUnfairLock(initialState: 0)

    var name: String { "Apple WeatherKit" }
    var lastHourCount: Int { hourCount.withLock { $0 } }
    var lastProvider: WeatherProvider { .apple }

    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let service = WeatherService.shared
        let current = try await service.weather(for: location, including: .current)
        // The past hours only feed the "snow lies" rule: a failure there must not lose the temperature.
        let forecast = try? await service.weather(
            for: location, including: .hourly(startDate: date.addingTimeInterval(-48 * 3600),
                                              endDate: date.addingTimeInterval(3600)))
        let hours = (forecast.map { Array($0) } ?? []).filter { $0.date <= date }.map {
            WeatherHour(date: $0.date, temperatureC: $0.temperature.converted(to: .celsius).value,
                        snowfallMm: $0.snowfallAmount.converted(to: .millimeters).value)
        }
        hourCount.withLock { $0 = hours.count }
        let temperature = current.temperature.converted(to: .celsius).value
        let mapped = WeatherRules.kind(appleCondition: current.condition.rawValue)
        return WeatherNow(
            temperatureC: temperature, kind: mapped.kind, intensity: mapped.intensity,
            cloudCover: current.cloudCover, isDaylight: current.isDaylight,
            snowOnGround: WeatherRules.snowOnGround(hours: hours, temperatureNow: temperature, kindNow: mapped.kind),
            observedAt: date,
            windSpeedMS: current.wind.speed.converted(to: .metersPerSecond).value,
            windFromDegrees: current.wind.direction.converted(to: .degrees).value)
    }
}

// MARK: - the second source and the fallback

/// MET Norway (api.met.no): free, no key. Respects `Expires`: while it has not passed, the remembered body answers.
final class MetNorwaySource: WeatherSource {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    enum Failure: LocalizedError {
        case status(Int)
        case notHTTP

        var errorDescription: String? {
            switch self {
            case .status(let code): "MET Norway answered HTTP \(code)"
            case .notHTTP: "MET Norway: no HTTP answer"
            }
        }
    }

    private struct Remembered { var body: Data; var expires: Date }

    private let transport: Transport
    private let clock: @Sendable () -> Date
    private let remembered = OSAllocatedUnfairLock(initialState: [URL: Remembered]())

    /// MET requires an identifying User-Agent; the public repo is the contact (never an e-mail address).
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "SleepHole/\(version) github.com/zrebec/sleephole"
    }

    static let defaultTransport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        return (data, http)
    }

    init(transport: @escaping Transport = MetNorwaySource.defaultTransport,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.clock = clock
    }

    var name: String { "MET Norway" }
    var lastHourCount: Int { 0 }
    var lastProvider: WeatherProvider { .metNorway }

    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow {
        let url = MetNorway.requestURL(for: place)
        let wall = clock()
        if let r = remembered.withLock({ $0[url] }), wall < r.expires {
            return try MetNorway.parse(r.body, now: date)
        }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, http) = try await transport(request)
        guard http.statusCode == 200 else { throw Failure.status(http.statusCode) }
        let value = try MetNorway.parse(data, now: date)
        if let header = http.value(forHTTPHeaderField: "Expires"), let expires = Self.httpDate(header) {
            remembered.withLock { $0[url] = Remembered(body: data, expires: expires) }
        }
        return value
    }

    private static func httpDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: s)
    }
}

/// Asks the primary source; when it throws, the secondary.
final class FallbackWeather: WeatherSource {
    private struct State { var provider: WeatherProvider; var note: String? }

    let primary: any WeatherSource
    let secondary: any WeatherSource
    private let state: OSAllocatedUnfairLock<State>

    init(primary: any WeatherSource, secondary: any WeatherSource) {
        self.primary = primary
        self.secondary = secondary
        state = OSAllocatedUnfairLock(initialState: State(provider: primary.lastProvider, note: nil))
    }

    struct BothFailed: LocalizedError, CustomStringConvertible {
        let first: String
        let second: String
        var errorDescription: String? { description }
        var description: String { "\(first); \(second)" }
    }

    var name: String { "\(primary.name) → \(secondary.name)" }
    var lastHourCount: Int { state.withLock { $0.provider == secondary.lastProvider ? secondary.lastHourCount : primary.lastHourCount } }
    var lastProvider: WeatherProvider { state.withLock { $0.provider } }
    var lastNote: String? { state.withLock { $0.note } }

    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow {
        do {
            let value = try await primary.now(at: place, date: date)
            state.withLock { $0 = State(provider: primary.lastProvider, note: nil) }
            return value
        } catch let firstError {
            let first = "\(primary.name) failed: \(Self.text(firstError))"
            do {
                let value = try await secondary.now(at: place, date: date)
                state.withLock { $0 = State(provider: secondary.lastProvider, note: first) }
                return value
            } catch let secondError {
                let second = "\(secondary.name) failed: \(Self.text(secondError))"
                state.withLock { $0.note = nil }
                throw BothFailed(first: first, second: second)
            }
        }
    }

    private static func text(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

// MARK: - which one the app runs with

enum WeatherSources {
    /// The source for this launch: tests → none; `-weather …` → a fixed simulated value (simulator and device);
    /// `-weatherSource met` → MET Norway alone, live (simulator and device, never under test); a real device →
    /// WeatherKit, and MET Norway when that fails; the simulator without arguments → none.
    @MainActor
    static func forLaunch(args: [String] = ProcessInfo.processInfo.arguments,
                          underTest: Bool = SystemAlarms.isRunningTests,
                          isDaylight: (@Sendable (Date) -> Bool)? = nil) -> any WeatherSource {
        if underTest { return NoWeather() }
        if let sim = WeatherSimulation.from(args: args) {
            return SimulatedWeather(simulation: sim, isDaylight: isDaylight ?? { _ in true })
        }
        if let i = args.firstIndex(of: "-weatherSource"), args.indices.contains(i + 1), args[i + 1] == "met" {
            return MetNorwaySource()
        }
        #if targetEnvironment(simulator)
        return NoWeather()
        #else
        return FallbackWeather(primary: WeatherKitSource(), secondary: MetNorwaySource())
        #endif
    }
}
