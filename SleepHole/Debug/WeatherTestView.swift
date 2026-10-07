import SleepCore
import SwiftUI

/// Settings → Developer → Weather test: what the weather source answered, what Today shows, and the simulation switch
/// (the same value will drive the rain and snow in the town, so it can be checked without waiting for real weather).
struct WeatherTestView: View {
    @Environment(AppModel.self) private var model
    @State private var refreshing = false

    /// The picker's rows: nil = live.
    private enum Choice: Hashable { case live, clear, cloudy, fog, rain, heavyRain, thunder, snow }

    private func choice(_ s: WeatherSimulation?) -> Choice {
        guard let s else { return .live }
        switch s.kind {
        case .clear: return .clear
        case .cloudy: return .cloudy
        case .fog: return .fog
        case .rain: return s.heavy ? .heavyRain : .rain
        case .thunder: return .thunder
        case .snow: return .snow
        }
    }

    private func simulation(_ c: Choice, keeping old: WeatherSimulation?) -> WeatherSimulation? {
        let kind: WeatherKind
        switch c {
        case .live: return nil
        case .clear: kind = .clear
        case .cloudy: kind = .cloudy
        case .fog: kind = .fog
        case .rain, .heavyRain: kind = .rain
        case .thunder: kind = .thunder
        case .snow: kind = .snow
        }
        return WeatherSimulation(kind: kind, heavy: c == .heavyRain, temperatureC: old?.temperatureC ?? 12,
                                 snowOnGround: old?.snowOnGround ?? false)
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func time(_ d: Date?) -> String { d.map { Fmt.timeSec($0) } ?? "–" }

    var body: some View {
        let store = model.weather
        let now = model.clock.now
        let daylight = LivingSky.state(at: now, settings: model.settings).daylight >= 0.5
        let shown = store.shown(for: model.settings.city, at: now, daylight: daylight)
        List {
            Section {
                row(L("Source"), store.source.name)
                row(L("City"), model.settings.city?.name ?? L("None"))
                row(L("Past hourly values"), "\(store.source.lastHourCount)")
            }
            Section {
                if let w = shown {
                    row(L("Temperature"), "\(String(format: "%.1f", w.temperatureC)) °C")
                    row(L("Kind"), "\(w.kind.title) \(WeatherRules.emoji(w))")
                    row(L("Intensity"), String(format: "%.2f", w.intensity))
                    row(L("Cloud cover"), String(format: "%.2f", w.cloudCover))
                    row(L("Daylight"), w.isDaylight ? L("Day") : L("Night"))
                    row(L("Snow on the ground"), w.snowOnGround ? L("Yes") : L("No"))
                    row(L("Observed at"), time(w.observedAt))
                } else {
                    Text(L("Today shows no weather.")).foregroundStyle(.secondary)
                }
            } header: { Text(L("Shown on Today")) }
            Section {
                row(L("Last success"), time(store.lastSuccess))
                row(L("Last failure"), time(store.lastFailure))
                row(L("Last error"), store.lastError ?? "–")
                Button(L("Refresh now")) {
                    refreshing = true
                    Task {
                        await store.refreshNow(city: model.settings.city, now: model.clock.now)
                        refreshing = false
                    }
                }
                .disabled(model.settings.city == nil || refreshing || store.activeSimulation != nil)
            } header: { Text(L("The source")) }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Weather")).font(.footnote).foregroundStyle(.secondary)
                    Picker(L("Weather"), selection: Binding(
                        get: { choice(store.simulation) },
                        set: { store.simulation = simulation($0, keeping: store.simulation) })) {
                        Text(L("Live")).tag(Choice.live)
                        Text(L("Clear")).tag(Choice.clear)
                        Text(L("Cloudy")).tag(Choice.cloudy)
                        Text(L("Fog")).tag(Choice.fog)
                        Text(L("Rain")).tag(Choice.rain)
                        Text(L("Heavy rain")).tag(Choice.heavyRain)
                        Text(L("Thunder")).tag(Choice.thunder)
                        Text(L("Snow")).tag(Choice.snow)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                if let sim = store.simulation {
                    Stepper(value: Binding(get: { Int(sim.temperatureC) },
                                           set: { store.simulation?.temperatureC = Double($0) }), in: -25...40) {
                        Text(L("Temperature: \(Int(sim.temperatureC)) °C"))
                    }
                    Toggle(L("Snow on the ground"), isOn: Binding(get: { sim.snowOnGround },
                                                                   set: { store.simulation?.snowOnGround = $0 }))
                }
            } header: { Text(L("Simulation")) } footer: {
                Text(L("A simulation lasts until you set it back to Live or the app restarts. It needs a city."))
            }
        }
        .navigationTitle(L("Weather test"))
    }
}
