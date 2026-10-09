import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI
import UIKit

// The system alarm (phase F6b): an AlarmKit alarm that rings in silent mode and during a Focus even when iOS has
// closed the app at night. It is the BACKUP of the in-app alarm, which stays THE alarm (the night rules R3 depend on
// it): scheduled when a night / nap starts, moved behind our own alarm when that really rings, cancelled by the
// wake-up confirmation. See docs/IMPLEMENTATION_PLAN.md, F6 "Final design of the system alarm".

/// What the phone lets SleepHole do with system alarms.
enum SystemAlarmConsent: Equatable {
    /// iOS < 26, or this build never uses the real thing (simulator, tests, `-mute`).
    case unavailable
    case notAsked
    case denied
    case allowed
}

/// THE system alarm: at most one is scheduled at a time.
@MainActor
protocol SystemAlarm: AnyObject {
    var consent: SystemAlarmConsent { get }
    /// Asks the owner once (iOS shows its own alert only while the state is `notAsked`) and returns the answer.
    func requestConsent() async -> SystemAlarmConsent
    /// Schedules THE one system alarm (replacing an earlier one). Returns false when it could not be scheduled.
    @discardableResult func schedule(at date: Date, soundFile: String) async -> Bool
    /// Cancels a scheduled alarm and stops a ringing one (every alarm of the app, the lock-screen warning too).
    func cancel()
    /// The lock-screen warning (B25/B26): a SEPARATE alarm that rings at once, so it can be heard over the Camera on the
    /// lock screen. It never touches THE alarm above. Returns false when it could not be set.
    /// The title carries the `seconds` the owner has left (the number the notification shows too).
    @discardableResult func ringWarning(soundFile: String, seconds: Int) async -> Bool
    /// Stops / cancels ONLY the warning alarm (ringing or still waiting).
    func stopWarning()
    /// Stops every alarm of the app that is ringing right now; alarms that still wait are left alone.
    func stopRinging()
}

extension SystemAlarmConsent {
    /// The state as the Settings row shows it.
    var title: String {
        switch self {
        case .allowed: L("On")
        case .denied: L("Not allowed")
        case .notAsked: L("Not asked yet")
        case .unavailable: L("Needs iOS 26")
        }
    }
}

enum SystemAlarmPlan {
    /// The system alarm first rings this long after the wake time; our own alarm gets the first word.
    static let afterWake: TimeInterval = 30
}

// MARK: - stand-ins (nothing here can ring)

/// iOS < 26, the simulator, tests and `-mute`: no system alarm at all.
@MainActor
final class NoSystemAlarm: SystemAlarm {
    var consent: SystemAlarmConsent { .unavailable }
    func requestConsent() async -> SystemAlarmConsent { .unavailable }
    func schedule(at date: Date, soundFile: String) async -> Bool { false }
    func cancel() {}
    func ringWarning(soundFile: String, seconds: Int) async -> Bool { false }
    func stopWarning() {}
    func stopRinging() {}
}

/// Dev aid for screenshots in the simulator (`-systemAlarm allowed|denied|notAsked`): reports a consent and remembers a
/// scheduled date, nothing more. It never rings.
@MainActor
final class SimulatedSystemAlarm: SystemAlarm {
    private(set) var consent: SystemAlarmConsent
    private(set) var scheduledAt: Date?

    init(consent: SystemAlarmConsent) { self.consent = consent }

    /// `-systemAlarm allowed|denied|notAsked` → the consent to pretend.
    static func consent(from args: [String]) -> SystemAlarmConsent? {
        guard let i = args.firstIndex(of: "-systemAlarm"), args.indices.contains(i + 1) else { return nil }
        switch args[i + 1] {
        case "allowed": return .allowed
        case "denied": return .denied
        case "notAsked": return .notAsked
        default: return nil
        }
    }

    func requestConsent() async -> SystemAlarmConsent {
        if consent == .notAsked { consent = .allowed }           // "the owner said yes"
        return consent
    }

    func schedule(at date: Date, soundFile: String) async -> Bool {
        guard consent == .allowed else { return false }
        scheduledAt = date
        return true
    }

    func cancel() { scheduledAt = nil }
    func ringWarning(soundFile: String, seconds: Int) async -> Bool { false }
    func stopWarning() {}
    func stopRinging() {}
}

// MARK: - which one the app runs with

@MainActor
enum SystemAlarms {
    /// True inside the unit-test host app.
    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    /// The system alarm for this launch. The real AlarmKit one exists only on a real device, outside tests and
    /// without `-mute`; the simulator never gets it (nothing may ring on the Mac), at most the silent stand-in.
    static func forLaunch(args: [String] = ProcessInfo.processInfo.arguments,
                          underTest: Bool = SystemAlarms.isRunningTests) -> any SystemAlarm {
        #if targetEnvironment(simulator)
        if !underTest, let consent = SimulatedSystemAlarm.consent(from: args) { return SimulatedSystemAlarm(consent: consent) }
        return NoSystemAlarm()
        #else
        if underTest || args.contains("-mute") { return NoSystemAlarm() }
        return AlarmKitSystemAlarm()
        #endif
    }
}

// MARK: - what the app remembers between launches

/// The system alarm the app believes is set, kept in UserDefaults so a relaunched app can still look after it.
struct SystemAlarmMemory {
    let defaults: UserDefaults
    static let atKey = "systemAlarm.at"
    static let safetyKey = "systemAlarm.safety"

    var at: Date? {
        get { defaults.object(forKey: Self.atKey) as? Date }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: Self.atKey) } else { defaults.removeObject(forKey: Self.atKey) }
        }
    }

    /// The alarm is a safety alarm (an early confirmation), not a night's backup.
    var isSafety: Bool {
        get { defaults.bool(forKey: Self.safetyKey) }
        nonmutating set {
            if newValue { defaults.set(true, forKey: Self.safetyKey) } else { defaults.removeObject(forKey: Self.safetyKey) }
        }
    }
}

// MARK: - the real thing (AlarmKit, iOS 26+)

/// The second button of the alarm: opens SleepHole (the confirm panel is on its night screen).
struct OpenSleepHoleIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open SleepHole"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

/// SleepHole's alarms carry no data of their own.
@available(iOS 26.0, *)
struct SleepHoleAlarmMetadata: AlarmMetadata {}

/// The real AlarmKit alarm. Only ever created on a real device (see `SystemAlarms.forLaunch`).
@MainActor
final class AlarmKitSystemAlarm: SystemAlarm {
    private let defaults: UserDefaults
    private static let idKey = "systemAlarm.id"
    private static let warningIDKey = "systemAlarm.warningID"
    /// AlarmKit needs a date in the future: the warning is scheduled this far ahead.
    static let warningLead: TimeInterval = 1.5

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The id of the alarm we scheduled last; kept so a relaunched app can still cancel it.
    private var storedID: UUID? {
        get { defaults.string(forKey: Self.idKey).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue { defaults.set(newValue.uuidString, forKey: Self.idKey) } else { defaults.removeObject(forKey: Self.idKey) }
        }
    }

    /// The id of the lock-screen warning alarm, kept under its own key (it is never THE alarm).
    private var warningID: UUID? {
        get { defaults.string(forKey: Self.warningIDKey).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue { defaults.set(newValue.uuidString, forKey: Self.warningIDKey) } else { defaults.removeObject(forKey: Self.warningIDKey) }
        }
    }

    var consent: SystemAlarmConsent {
        guard #available(iOS 26.0, *) else { return .unavailable }
        switch AlarmManager.shared.authorizationState {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .authorized: return .allowed
        @unknown default: return .denied
        }
    }

    func requestConsent() async -> SystemAlarmConsent {
        guard #available(iOS 26.0, *) else { return .unavailable }
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        return consent
    }

    @discardableResult
    func schedule(at date: Date, soundFile: String) async -> Bool {
        guard #available(iOS 26.0, *), consent == .allowed, date.timeIntervalSinceNow > 1 else { return false }
        let id = UUID()
        do {
            try await Self.submit(id: id, at: date, soundFile: soundFile)
        } catch {
            return false                                    // an earlier alarm, if any, stays
        }
        let previous = storedID
        storedID = id
        if let previous, previous != id { Self.end(id: previous) }   // the new one is set first: never a gap without an alarm
        return true
    }

    func cancel() {
        guard #available(iOS 26.0, *) else { return }
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        for alarm in alarms { Self.end(alarm) }
        if let id = storedID, !alarms.contains(where: { $0.id == id }) { Self.end(id: id) }   // fired and gone, or not listed
        storedID = nil
        warningID = nil
    }

    func ringWarning(soundFile: String, seconds: Int) async -> Bool {
        guard #available(iOS 26.0, *), consent == .allowed else { return false }
        if let previous = warningID { Self.end(id: previous) }
        let id = UUID()
        do {
            try await Self.submitWarning(id: id, at: Date().addingTimeInterval(Self.warningLead), soundFile: soundFile,
                                           seconds: seconds)
        } catch {
            warningID = nil
            return false
        }
        warningID = id
        return true
    }

    func stopWarning() {
        guard #available(iOS 26.0, *), let id = warningID else { return }
        Self.end(id: id)
        warningID = nil
    }

    func stopRinging() {
        guard #available(iOS 26.0, *) else { return }
        for alarm in (try? AlarmManager.shared.alarms) ?? [] where alarm.state == .alerting {
            try? AlarmManager.shared.stop(id: alarm.id)
        }
    }

    // MARK: AlarmKit calls

    /// The one call that sets an alarm. The configuration is built here, on the same side of the isolation line as
    /// the AlarmKit call (it is not Sendable).
    @available(iOS 26.0, *)
    private nonisolated static func submit(id: UUID, at date: Date, soundFile: String) async throws {
        let attributes = AlarmAttributes<SleepHoleAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert()), tintColor: .indigo)
        let configuration = AlarmManager.AlarmConfiguration<SleepHoleAlarmMetadata>.alarm(
            schedule: .fixed(date), attributes: attributes, secondaryIntent: OpenSleepHoleIntent(),
            sound: .named(soundFile))
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    /// The lock-screen warning: `.fixed` a moment from now, only the system's stop control (no "Open SleepHole": opening
    /// the app from the lock screen needs Face ID / the passcode, the wrong advice here), no secondary intent.
    @available(iOS 26.0, *)
    private nonisolated static func submitWarning(id: UUID, at date: Date, soundFile: String, seconds: Int) async throws {
        let attributes = AlarmAttributes<SleepHoleAlarmMetadata>(
            presentation: AlarmPresentation(alert: warningAlert(seconds: seconds)), tintColor: .orange)
        let configuration = AlarmManager.AlarmConfiguration<SleepHoleAlarmMetadata>.alarm(
            schedule: .fixed(date), attributes: attributes, sound: .named(soundFile))
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    @available(iOS 26.0, *)
    private nonisolated static func warningAlert(seconds: Int) -> AlarmPresentation.Alert {
        let title = LocalizedStringResource("Your phone is off duty – switch the screen off within \(seconds) seconds")
        if #available(iOS 26.1, *) { return AlarmPresentation.Alert(title: title) }
        let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.circle")
        return AlarmPresentation.Alert(title: title, stopButton: stop)
    }

    /// "Good morning ☀️" with the Stop button (the system's own on iOS 26.1+) and "Open SleepHole".
    @available(iOS 26.0, *)
    private nonisolated static func alert() -> AlarmPresentation.Alert {
        let title = LocalizedStringResource("Good morning ☀️")
        let open = AlarmButton(text: LocalizedStringResource("Open SleepHole"), textColor: .white,
                               systemImageName: "moon.zzz.fill")
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title, secondaryButton: open, secondaryButtonBehavior: .custom)
        }
        let stop = AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.circle")
        return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: open, secondaryButtonBehavior: .custom)
    }

    /// A ringing alarm is stopped, a waiting one cancelled.
    @available(iOS 26.0, *)
    private static func end(_ alarm: Alarm) {
        if alarm.state == .alerting { try? AlarmManager.shared.stop(id: alarm.id) } else { try? AlarmManager.shared.cancel(id: alarm.id) }
    }

    @available(iOS 26.0, *)
    private static func end(id: UUID) {
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
    }
}

// MARK: - keeping the app alive (B28)

/// A background task for the time the lock-screen warning alarm rings: the alarm takes our audio session away and iOS
/// would suspend the app, so the warning's deadline could never run. A seam so tests can count begin / end.
@MainActor
protocol KeepAlive: AnyObject {
    /// Starts the task; `onExpire` runs when iOS takes the time away (the owner of the token must then call `end`).
    func begin(name: String, onExpire: @escaping @MainActor () -> Void) -> Int
    func end(_ token: Int)
}

/// The default (tests, previews): keeps nothing alive.
@MainActor
final class NoKeepAlive: KeepAlive {
    func begin(name: String, onExpire: @escaping @MainActor () -> Void) -> Int { 0 }
    func end(_ token: Int) {}
}

/// The real thing: a UIKit background task.
@MainActor
final class UIKitKeepAlive: KeepAlive {
    func begin(name: String, onExpire: @escaping @MainActor () -> Void) -> Int {
        UIApplication.shared.beginBackgroundTask(withName: name) { Task { @MainActor in onExpire() } }.rawValue
    }

    func end(_ token: Int) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token))
    }
}
