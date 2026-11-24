import AVFoundation
import Foundation
import OSLog
import SleepCore
import UIKit

/// The diagnostic track of a night / nap (13ab, owner 2026-11-11): a second, separate record of what the phone did –
/// sound, calls, alarm, volume, screen, battery, the app's lifecycle – kept next to the rule journal.
///
///  * It only ever writes to the ACTIVE night / nap record (`NightRecord.diagData`), from `begin` until `end`.
///  * It never changes what a night counts and never leaves the phone: not in a backup, not in the sync file, not in a
///    fingerprint. Writes do NOT go through `AppModel.append` / `AppModel.save()`: no `dataRevision` bump, no sync wake-up.
///  * Entries wait in memory and are saved coalesced – at most once every `flushInterval` seconds – plus at once at the
///    moments that matter (`flush()`: background, the alarm, the end of the night, termination).
///  * Only device state is ever written: enums and whole percentages – never a number, a name, an app, a port's name,
///    the wake code, the city or a Health value.
@MainActor
final class Diagnostics {
    static let flushInterval: TimeInterval = 15
    private static let log = Logger(subsystem: "sk.zrebec.sleephole", category: "night")
    private static let batteryOwner = "diagnostics"

    /// Injected time (tests use the model's fake clock).
    var now: () -> Date = { Date() }
    /// Saves the model context (`AppModel` passes a plain `context.save()` – never its `save()`).
    var commit: () -> Void = {}
    /// Timers and system observers run only in the app, never in unit tests.
    var observesSystem = false

    /// How many times the context was saved for the track (tests: "not once per entry").
    private(set) var saves = 0
    private(set) var record: NightRecord?
    private(set) var buffer: [DiagEntry] = []
    /// The setup's end was noted already (once per night).
    var setupEndNoted = false
    /// The stored log reached its cap: nothing more is buffered or saved.
    private var storedFull = false

    private var lastFlush: Date?
    private var timer: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []

    var isTracking: Bool { record != nil }

    // MARK: lifetime

    /// Starts the track of `rec` (a new night / nap, or the running one after a relaunch). Entries already stored with
    /// the record stay – a relaunch continues the same track.
    func begin(_ rec: NightRecord) {
        if record != nil { end() }
        record = rec
        buffer = []
        storedFull = rec.diagLog.isFull
        lastFlush = now()          // the caller saves right after its start entries; later ones wait for the interval
        setupEndNoted = false
        if observesSystem { observeSystem() }
    }

    /// Writes what is waiting, stops tracking and lets go of the battery switch. Called when the night is finalized.
    func end() {
        flush()
        timer?.cancel(); timer = nil
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        if observesSystem { BatteryMonitoring.set(Self.batteryOwner, on: false) }
        record = nil
    }

    // MARK: writing

    /// Adds one line to the active night's track. With nothing running it does nothing.
    func note(_ k: String, _ v: String? = nil) {
        guard record != nil, !storedFull else { return }
        let at = now()
        buffer.append(DiagEntry(at: at, k: k, v: v))
        #if DEBUG
        Self.log.debug("\(k, privacy: .public) \(v ?? "", privacy: .public)")
        #endif
        if let last = lastFlush, at.timeIntervalSince(last) < Self.flushInterval {
            scheduleFlush(after: Self.flushInterval - at.timeIntervalSince(last))
        } else {
            flush()
        }
    }

    /// Saves the waiting entries now (a no-op when there are none). The one place the context is saved for the track.
    func flush() {
        timer?.cancel(); timer = nil
        guard let rec = record, !buffer.isEmpty else { return }
        var log = rec.diagLog
        let before = log.entries.count
        log.append(contentsOf: buffer)
        buffer = []
        storedFull = log.isFull
        guard log.entries.count != before else { return }       // nothing changed: no assignment, no save
        rec.diagData = log.encoded()
        commit()
        saves += 1
        lastFlush = now()
    }

    /// Drops the track of every finished night / nap older than `DiagLog.retentionDays` (one pass, one save; the active
    /// record and everything but `diagData` stay untouched). Called when a night is finalized.
    func prune(_ records: [NightRecord]) {
        var changed = false
        for r in records where r !== record && r.diagData != nil
            && DiagLog.isStale(finalizedAt: r.finalizedAt, now: now()) {
            r.diagData = nil
            changed = true
        }
        if changed { commit(); saves += 1 }
    }

    private func scheduleFlush(after seconds: TimeInterval) {
        guard observesSystem, timer == nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, seconds)))
            guard !Task.isCancelled else { return }
            self?.timer = nil
            self?.flush()
        }
    }

    // MARK: battery and power

    /// k=power: battery, plug state and Low Power Mode right now (`reason` goes in front, e.g. "setup", "locked").
    func notePower(_ reason: String? = nil) {
        note("power", ([reason].compactMap { $0 } + [DeviceReading.powerText()]).joined(separator: " "))
    }

    private func observeSystem() {
        BatteryMonitoring.set(Self.batteryOwner, on: true)
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, _ text: @escaping @MainActor () -> String) {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.note("power", text()) }
            })
        }
        observe(.NSProcessInfoPowerStateDidChange) { "lpm=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0)" }
        observe(UIDevice.batteryStateDidChangeNotification) { "state=\(DeviceReading.batteryStateName()) batt=\(DeviceReading.batteryPercentText())" }
        observe(ProcessInfo.thermalStateDidChangeNotification) { "thermal=\(DeviceReading.thermalName())" }
    }
}

/// Reads of the device's state for the track: enums and whole percentages only.
@MainActor
enum DeviceReading {
    static func batteryPercentText() -> String {
        let l = UIDevice.current.batteryLevel
        return l < 0 ? "na" : "\(Int((l * 100).rounded()))"
    }

    static func batteryStateName() -> String {
        switch UIDevice.current.batteryState {
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        default: "unknown"
        }
    }

    static func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// "batt=87 state=charging lpm=0"
    static func powerText() -> String {
        "batt=\(batteryPercentText()) state=\(batteryStateName()) lpm=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0)"
    }

    static func brightnessPercent() -> String {
        let b = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.brightness }.first
        return b.map { "\(Int(($0 * 100).rounded()))" } ?? "na"
    }

    /// The media volume as a whole percent (what `AVAudioSession` reports; 0 under test).
    static func volumePercent() -> String { "\(Int((AVAudioSession.sharedInstance().outputVolume * 100).rounded()))" }

    /// The TYPES of the current audio outputs (never a device's name), e.g. "speaker", "bluetoothA2DP".
    static func routeTypes() -> String {
        let types = AVAudioSession.sharedInstance().currentRoute.outputs.map { portName($0.portType) }
        return types.isEmpty ? "none" : types.joined(separator: ",")
    }

    static func portName(_ port: AVAudioSession.Port) -> String {
        switch port {
        case .builtInSpeaker: "speaker"
        case .builtInReceiver: "receiver"
        case .headphones: "headphones"
        case .bluetoothA2DP: "bluetoothA2DP"
        case .bluetoothHFP: "bluetoothHFP"
        case .bluetoothLE: "bluetoothLE"
        case .airPlay: "airPlay"
        case .carAudio: "carAudio"
        case .HDMI: "hdmi"
        case .usbAudio: "usb"
        case .lineOut: "lineOut"
        default: "other"
        }
    }

    static func appVersionText() -> String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v)(\(b))"
    }
}
