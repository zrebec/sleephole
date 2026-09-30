import Foundation
import SleepCore

/// Everything the owner can set. Persisted as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var schedule = Schedule()
    var ambience: AudioKeeper.Ambience = .brownNoise
    var volume: Float = 0.15
    /// Sleep timer for the night sound: nil = all night.
    var ambienceMinutes: Int?
    /// Afternoon rest. Optional in the JSON so settings saved by older builds still load.
    var napPlan: NapPlan?
    var nap: NapPlan {
        get { napPlan ?? .default }
        set { napPlan = newValue }
    }
    static let ambienceTimerOptions: [Int?] = [1, 5, 15, 30, 45, 60, nil]
    var ambienceSeconds: TimeInterval? { ambienceMinutes.map { Double($0) * 60 } }

    static func timerTitle(_ minutes: Int?) -> String {
        minutes.map { $0 == 1 ? L("1 min (test)") : L("\($0) min") } ?? L("All night")
    }
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
            case .gentle: L("Gentle")
            case .morning: L("Morning Mood")
            case .ode: L("Ode to Joy")
            case .chimes: L("Chimes")
            case .retro: L("Retro")
            case .bugle: L("Reveille")
            case .digital: L("Digital")
            case .alert: L("Alarm!")
            }
        }

        var detail: String {
            switch self {
            case .gentle: L("Pizzicato, slowly getting louder.")
            case .morning: L("Grieg – Peer Gynt, flute.")
            case .ode: L("Beethoven – music box.")
            case .chimes: L("Rising bells.")
            case .retro: L("Retro tune, slowly getting louder.")
            case .bugle: L("Trumpet, quickly getting louder.")
            case .digital: L("Beep-beep-beep, full volume at once.")
            case .alert: L("Aggressive beeping, full volume at once.")
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
