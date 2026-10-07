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
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow
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
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow { throw WeatherSourceError.unavailable }
}

/// What a simulation (launch arguments or the Developer screen) pretends the weather is.
struct WeatherSimulation: Codable, Equatable {
    var kind: WeatherKind
    var heavy: Bool
    var temperatureC: Double
    var snowOnGround: Bool

    init(kind: WeatherKind, heavy: Bool = false, temperatureC: Double = 12, snowOnGround: Bool = false) {
        self.kind = kind
        self.heavy = heavy
        self.temperatureC = temperatureC
        self.snowOnGround = snowOnGround
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
                          isDaylight: isDaylight, snowOnGround: snowOnGround || kind == .snow, observedAt: date)
    }

    /// `-weather clear|cloudy|fog|rain|heavyRain|thunder|snow`, `-weatherTemp 14`, `-weatherSnowCover`; nil without `-weather`.
    static func from(args: [String]) -> WeatherSimulation? {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        guard let word = value("-weather") else { return nil }
        let heavy = word == "heavyRain"
        guard let kind = WeatherKind(rawValue: heavy ? "rain" : word) else { return nil }
        return WeatherSimulation(kind: kind, heavy: heavy, temperatureC: value("-weatherTemp").flatMap(Double.init) ?? 12,
                                 snowOnGround: args.contains("-weatherSnowCover"))
    }
}

/// A fixed value as a source (launch arguments `-weather …`).
struct SimulatedWeather: WeatherSource {
    let simulation: WeatherSimulation
    /// Day or night at the given moment.
    let isDaylight: @Sendable (Date) -> Bool

    var name: String { "simulated" }
    var lastHourCount: Int { 0 }
    func now(at place: GeoPoint, date: Date) async throws -> WeatherNow {
        simulation.value(at: date, isDaylight: isDaylight(date))
    }
}

// MARK: - the real thing (Apple WeatherKit)

final class WeatherKitSource: WeatherSource {
    private let hourCount = OSAllocatedUnfairLock(initialState: 0)

    var name: String { "Apple WeatherKit" }
    var lastHourCount: Int { hourCount.withLock { $0 } }

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
            observedAt: date)
    }
}

// MARK: - which one the app runs with

enum WeatherSources {
    /// The source for this launch: tests → none; `-weather …` → a fixed simulated value (simulator and device); a real
    /// device → WeatherKit; the simulator without arguments → none.
    @MainActor
    static func forLaunch(args: [String] = ProcessInfo.processInfo.arguments,
                          underTest: Bool = SystemAlarms.isRunningTests,
                          isDaylight: (@Sendable (Date) -> Bool)? = nil) -> any WeatherSource {
        if underTest { return NoWeather() }
        if let sim = WeatherSimulation.from(args: args) {
            return SimulatedWeather(simulation: sim, isDaylight: isDaylight ?? { _ in true })
        }
        #if targetEnvironment(simulator)
        return NoWeather()
        #else
        return WeatherKitSource()
        #endif
    }
}
