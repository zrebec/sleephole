import Foundation
import Observation
import SleepCore

/// What Today shows and what the town will draw: the last weather value for the owner's city, with its caching,
/// rate limits and the simulation switch. Kept in its own UserDefaults key – not in `AppSettings`, not in backups.
@MainActor
@Observable
final class WeatherStore {
    /// The cached value together with the place it belongs to.
    private struct Stored: Codable {
        var weather: WeatherNow
        var latitude: Double
        var longitude: Double
        var lastSuccess: Date
    }

    static let cacheKey = "weather.cache"

    let source: any WeatherSource
    @ObservationIgnored private let defaults: UserDefaults
    /// Set by the launch arguments: one launch only, never stored.
    @ObservationIgnored private let launchSimulation: WeatherSimulation?
    @ObservationIgnored private var inFlight = false

    private(set) var weather: WeatherNow?
    private var place: (latitude: Double, longitude: Double)?
    private(set) var lastSuccess: Date?
    private(set) var lastFailure: Date?
    private(set) var lastError: String?

    /// The Developer switch (Weather test); nil = live. In memory only: it lasts until it is set back or the app restarts,
    /// so a forgotten simulation can never show fake weather for days.
    var simulation: WeatherSimulation?

    init(source: any WeatherSource, defaults: UserDefaults = .standard, launchSimulation: WeatherSimulation? = nil) {
        self.source = source
        self.defaults = defaults
        self.launchSimulation = launchSimulation
        if let data = defaults.data(forKey: Self.cacheKey), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            weather = s.weather
            place = (s.latitude, s.longitude)
            lastSuccess = s.lastSuccess
        }
    }

    /// The store for this launch (see `WeatherSources.forLaunch`).
    static func forLaunch(defaults: UserDefaults = .standard, args: [String] = ProcessInfo.processInfo.arguments,
                          underTest: Bool = SystemAlarms.isRunningTests) -> WeatherStore {
        WeatherStore(source: WeatherSources.forLaunch(args: args, underTest: underTest), defaults: defaults,
                     launchSimulation: underTest ? nil : WeatherSimulation.from(args: args))
    }

    /// The simulation in force: the launch arguments win over the Developer switch.
    var activeSimulation: WeatherSimulation? { launchSimulation ?? simulation }

    /// What Today shows: the simulated value, else the cached one if it belongs to this city and is fresh. Nothing
    /// without a city. `daylight` is the sky's day / night NOW, applied to the live value too (the cached one is from
    /// fetch time and can be 90 minutes old).
    func shown(for city: SkyCity?, at now: Date, daylight: Bool) -> WeatherNow? {
        guard let city else { return nil }
        if let sim = activeSimulation { return sim.value(at: now, isDaylight: daylight) }
        guard let w = weather, belongs(to: city), WeatherRules.isFresh(w, at: now) else { return nil }
        var shown = w
        shown.isDaylight = daylight
        return shown
    }

    private func belongs(to city: SkyCity) -> Bool {
        place.map { $0.latitude == city.latitude && $0.longitude == city.longitude } ?? false
    }

    /// A different city: the old value is dropped at once (it is not this city's weather).
    func sync(city: SkyCity?) {
        guard weather != nil || place != nil else { return }
        if let city, belongs(to: city) { return }
        weather = nil
        place = nil
        lastSuccess = nil
        defaults.removeObject(forKey: Self.cacheKey)
    }

    /// Asks the source when the rules allow it. Never during a night or nap, never without a city.
    func refreshIfNeeded(city: SkyCity?, now: Date, nightActive: Bool) async {
        sync(city: city)
        guard let city, !nightActive, activeSimulation == nil,
              WeatherRules.shouldRefresh(lastSuccess: lastSuccess, lastFailure: lastFailure, now: now) else { return }
        await fetch(city: city, now: now)
    }

    /// The test screen's button: ignores the rate limit, not the missing city.
    func refreshNow(city: SkyCity?, now: Date) async {
        sync(city: city)
        guard let city else { return }
        await fetch(city: city, now: now)
    }

    private func fetch(city: SkyCity, now: Date) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            let value = try await source.now(at: city.place, date: now)
            weather = value
            place = (city.latitude, city.longitude)
            lastSuccess = now
            lastError = nil
            if let data = try? JSONEncoder().encode(Stored(weather: value, latitude: city.latitude,
                                                           longitude: city.longitude, lastSuccess: now)) {
                defaults.set(data, forKey: Self.cacheKey)
            }
        } catch {
            lastFailure = now
            lastError = String(describing: error)          // the cached value stays until it is stale
        }
    }
}
