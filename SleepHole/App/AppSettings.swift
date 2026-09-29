import Foundation
import SleepCore

/// Everything the owner can set. Persisted as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var schedule = Schedule()
    var ambience: AudioKeeper.Ambience = .brownNoise
    var volume: Float = 0.15
    var alarmSound: AlarmSound = .gentle
    /// Typed on the alarm screen as an alternative to shaking (D15).
    var wakeCode: String = AppSettings.randomCode()

    enum AlarmSound: String, Codable, CaseIterable, Identifiable {
        case gentle = "alarm_gentle"          // default
        case morning = "alarm_morning"
        case ode = "alarm_ode"
        case chimes = "alarm_chimes"
        case retro = "alarm_retro"
        case bugle = "alarm_bugle"
        case digital = "alarm_digital"
        case alert = "alarm_alert"

        var id: String { rawValue }
        var fileName: String { rawValue + ".caf" }

        var title: String {
            switch self {
            case .gentle: "Jemný (pizzicato)"
            case .morning: "Ranná nálada (Grieg)"
            case .ode: "Óda na radosť (hracia skrinka)"
            case .chimes: "Zvonkohra"
            case .retro: "Retro"
            case .bugle: "Budíček (trúbka)"
            case .digital: "Digitálny budík"
            case .alert: "Poplach (agresívny)"
            }
        }

        /// Seconds to ramp from quiet to full volume; 0 = full blast immediately.
        var rampSeconds: Double {
            switch self {
            case .gentle, .retro: 60
            case .morning, .ode: 45
            case .chimes: 30
            case .bugle: 10
            case .digital, .alert: 0
            }
        }
    }

    static func randomCode() -> String { String(format: "%04d", Int.random(in: 0...9999)) }

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
