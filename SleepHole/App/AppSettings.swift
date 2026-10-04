import Foundation
import UIKit
import SleepCore

/// The owner's city for the real sky (Settings → Sky): verified through Apple Maps, stored with its coordinates.
struct SkyCity: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double

    var place: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

/// Everything the owner can set. Persisted as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var schedule = Schedule()
    var ambience: AudioKeeper.Ambience = .brownNoise
    var volume: Float = 0.15
    /// Sleep timer for the night sound: nil = all night.
    var ambienceMinutes: Int?
    /// Set when the owner stopped the sleep sound during a night or nap (bug B19): the next night / nap then starts
    /// silent, the chosen sound and duration stay. nil = on. Optional so settings saved by older builds still load.
    var ambienceOff: Bool?
    /// Settings switch "Play when the night starts" (on = `ambienceOff` is nil).
    var playsAtStart: Bool {
        get { ambienceOff != true }
        set { ambienceOff = newValue ? nil : true }
    }
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
    /// Appearance + sounds (owner 2026-10-02). Optional in the JSON so settings saved by older builds still load.
    var themeRaw: AppTheme?
    var theme: AppTheme {
        get { themeRaw ?? .system }
        set { themeRaw = newValue }
    }
    /// The city of the real sun and moon on Today (plan SKY). nil = no city: the sky follows the sleep schedule.
    /// Optional in the JSON (and in backups) so settings saved by older builds still load.
    var city: SkyCity?
    var soundEffectsOff: Bool?
    var soundEffects: Bool {
        get { soundEffectsOff != true }
        set { soundEffectsOff = newValue ? nil : true }
    }
    var voiceOff: Bool?
    var voice: Bool {
        get { voiceOff != true }
        set { voiceOff = newValue ? nil : true }
    }
    /// Typed on the alarm screen as an alternative to shaking (D15).
    var wakeCode: String = AppSettings.randomCode()

    enum AlarmSound: String, Codable, CaseIterable, Identifiable {
        case gentle = "alarm_gentle"          // default
        case birds = "alarm_birds"            // CC0 recordings (Freesound) + Bach, owner 2026-09-30
        case bowl = "alarm_bowl"
        case musicBox = "alarm_musicbox"
        case kalimba = "alarm_kalimba"
        case bach = "alarm_bach"
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
            case .birds: L("Dawn chorus")
            case .bowl: L("Singing bowl")
            case .musicBox: L("Music box")
            case .kalimba: L("Kalimba")
            case .bach: L("Prelude")
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
            case .birds: L("Birds singing at dawn, slowly getting louder.")
            case .bowl: L("A Tibetan singing bowl, the strikes come closer together.")
            case .musicBox: L("An old Symphonion music box – “Klosterglocken”.")
            case .kalimba: L("A gentle kalimba melody.")
            case .bach: L("Bach – Prelude in C major, harp.")
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
            case .gentle, .retro, .birds: 60
            case .bowl, .musicBox, .kalimba, .bach: 45
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

/// Light / dark / follow the iPhone. Applied to every window (`overrideUserInterfaceStyle`) – SwiftUI's
/// `preferredColorScheme(nil)` does not reliably go back to the system appearance.
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("System")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows where window.overrideUserInterfaceStyle != style {
                UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
                    window.overrideUserInterfaceStyle = self.style
                }
            }
        }
    }
}
