import SleepCore
import SwiftUI

extension Fmt {
    /// Fahrenheit only where the region measures that way (the US); everywhere else °C. The region, not the UI
    /// language: an English-speaking owner in Slovakia still gets °C.
    static var usesFahrenheit: Bool { Locale.current.measurementSystem == .us }

    /// The number shown before the degree sign: whole degrees, in the region's unit, never "-0".
    static func degrees(_ celsius: Double, fahrenheit: Bool = Fmt.usesFahrenheit) -> Int {
        WeatherRules.roundedDegrees(fahrenheit ? celsius * 9 / 5 + 32 : celsius)
    }
}

extension WeatherKind {
    /// The kind in words (the badge's accessibility label, the Weather test screen).
    var title: String {
        switch self {
        case .clear: L("Clear")
        case .cloudy: L("Cloudy")
        case .fog: L("Fog")
        case .rain: L("Rain")
        case .thunder: L("Thunder")
        case .snow: L("Snow")
        }
    }
}

/// The text of Today's weather badge: only the number and the emoji, e.g. "14° 🌧️".
enum WeatherLabel {
    static func text(_ w: WeatherNow, fahrenheit: Bool = Fmt.usesFahrenheit) -> String {
        "\(Fmt.degrees(w.temperatureC, fahrenheit: fahrenheit))° \(WeatherRules.emoji(w))"
    }

    static func accessibility(_ w: WeatherNow, fahrenheit: Bool = Fmt.usesFahrenheit) -> String {
        "\(w.kind.title) \(Fmt.degrees(w.temperatureC, fahrenheit: fahrenheit))°"
    }
}

/// The weather badge in Today's navigation bar (top right) and the refresh loop (every minute – the rules rate-limit the
/// requests –, when the app becomes active, and when the city changes). A request never starts during a night or nap.
/// The title and the sky's semicircle are untouched. No value: no bar item at all (an empty one leaves an empty capsule).
struct TodayWeatherModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped every minute so the badge is re-evaluated: a stale value goes, the day / night emoji follows the sky.
    @State private var tick = 0

    func body(content: Content) -> some View {
        _ = tick
        let now = model.clock.now
        let daylight = LivingSky.state(at: now, settings: model.settings).daylight >= 0.5
        let shown = model.weather.shown(for: model.settings.city, at: now, daylight: daylight)
        return content
            .toolbar {
                if let w = shown {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(verbatim: WeatherLabel.text(w))
                            .foregroundStyle(.primary)
                            .accessibilityLabel(WeatherLabel.accessibility(w))
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    await refresh()
                    try? await Task.sleep(for: .seconds(60))
                    tick += 1
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { tick += 1; Task { await refresh() } }
            }
            .onChange(of: model.settings.city) { _, _ in tick += 1; Task { await refresh() } }
    }

    private func refresh() async {
        await model.weather.refreshIfNeeded(city: model.settings.city, now: model.clock.now, nightActive: model.active != nil)
    }
}

extension View {
    /// Today's weather badge, plus the refresh loop.
    func todayWeather() -> some View { modifier(TodayWeatherModifier()) }
}

/// The credit both providers require. Apple (WeatherKit rules): the Apple Weather mark and the legal link to the other
/// data sources. MET Norway (its licence): the data credit and a link to the licensing page.
struct WeatherAttribution: View {
    static let legalURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
    static let metLicenceURL = URL(string: "https://www.met.no/en/free-meteorological-data/Licensing-and-crediting")!
    /// The Apple logo character (U+F8FF) followed by " Weather".
    static let mark = "\u{F8FF} Weather"

    /// Whose value is shown; a simulation or no value yet keeps Apple's credit.
    var provider: WeatherProvider = .apple

    var body: some View {
        HStack(spacing: 8) {
            // primary colour, not the link tint: the tint is unreadable on the light sky (seen in the simulator)
            if provider == .metNorway {
                Text(L("Weather data: MET Norway")).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                Link(L("Licence and credit"), destination: Self.metLicenceURL)
                    .font(.footnote).underline().foregroundStyle(.primary)
            } else {
                Text(verbatim: Self.mark).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                Link(L("Other data sources"), destination: Self.legalURL)
                    .font(.footnote).underline().foregroundStyle(.primary)
            }
        }
    }
}
