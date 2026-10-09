import AVFoundation
import CoreMotion
import Foundation
import UIKit

/// Developer-only recorder for measuring what iOS reports while the lock screen is used (filming, a notification
/// lighting the screen, a charger, …). Runs only during a DEBUG night launched with `-lockLab` (see `shouldRecord`).
/// Appends plain-text lines to `Application Support/lock-lab.log`; it changes no rule.
@MainActor
final class LockLab {
    /// Peaks of one sampling window; reading resets them.
    struct Peaks: Equatable {
        private(set) var acceleration = 0.0
        private(set) var rotation = 0.0
        private(set) var gravity: (x: Double, y: Double, z: Double) = (0, 0, 0)

        mutating func feed(acceleration a: (x: Double, y: Double, z: Double),
                           rotation r: (x: Double, y: Double, z: Double),
                           gravity g: (x: Double, y: Double, z: Double)) {
            acceleration = max(acceleration, (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
            rotation = max(rotation, (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot())
            gravity = g
        }

        /// Returns the peaks and the latest gravity, then resets the peaks (gravity is kept).
        mutating func readAndReset() -> (acceleration: Double, rotation: Double, gravity: (x: Double, y: Double, z: Double)) {
            let out = (acceleration, rotation, gravity)
            acceleration = 0; rotation = 0
            return out
        }

        static func == (l: Peaks, r: Peaks) -> Bool {
            l.acceleration == r.acceleration && l.rotation == r.rotation && l.gravity == r.gravity
        }
    }

    static let maxLogBytes = 2_000_000
    static let darwinNames = ["com.apple.iokit.hid.displayStatus", "com.apple.springboard.pluggedin",
                              "com.apple.backboardd.backlight.changed", "com.apple.springboard.DeviceLockStatus"]
    static let blankedName = "com.apple.springboard.hasBlankedScreen"

    /// The lab records only a DEBUG night of a process launched with `-lockLab`.
    static func shouldRecord(arguments: [String], isDebugNight: Bool) -> Bool {
        isDebugNight && arguments.contains("-lockLab")
    }

    /// `s lit=… data=… app=… bright=… batt=… acc=… rot=… grav=x,y,z orient=… bg=<seconds of background time left or inf>`; `lit` nil = not known yet.
    static func sampleLine(lit: Bool?, protectedData: Bool, app: String, brightness: Double, battery: String,
                           acceleration: Double, rotation: Double,
                           gravity: (x: Double, y: Double, z: Double), orientation: String,
                           backgroundRemaining: Double) -> String {
        let litText = lit.map { $0 ? "1" : "0" } ?? "?"
        func f(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
        return "s lit=\(litText) data=\(protectedData ? 1 : 0) app=\(app) bright=\(f(brightness, 2)) batt=\(battery) "
            + "acc=\(f(acceleration, 3)) rot=\(f(rotation, 2)) grav=\(f(gravity.x, 2)),\(f(gravity.y, 2)),\(f(gravity.z, 2)) "
            + "orient=\(orientation) bg=\(backgroundRemaining > 1e6 ? "inf" : f(backgroundRemaining, 1))"
    }

    private(set) var isRunning = false
    let fileURL: URL
    private var handle: FileHandle?
    private let darwin = DarwinNotifications()
    private var tokens: [NSObjectProtocol] = []
    private var motion: CMMotionManager?
    private var peaks = Peaks()
    private var sampler: Timer?
    private var blanked: Bool?
    private var batteryWasMonitored = false

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// `directory` defaults to Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("lock-lab.log")
    }

    func start() {
        guard !isRunning else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if size > Self.maxLogBytes || !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
        isRunning = true
        var info = utsname(); uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        note("=== lab started · iOS \(UIDevice.current.systemVersion) · \(model) ===")

        // Darwin: own instance (the shared one belongs to LifecycleMonitor)
        for name in Self.darwinNames { note("initial \(name) state=\(DarwinNotifications.currentState(of: name))") }
        blanked = DarwinNotifications.currentState(of: Self.blankedName) == 1
        note("initial \(Self.blankedName) state=\(blanked == true ? 1 : 0)")
        darwin.observe(Self.darwinNames + [Self.blankedName]) { [weak self] name, state in
            guard let self else { return }
            if name == Self.blankedName { self.blanked = state == 1; return }   // the monitor's raw log carries the line
            self.note("darwin \(name) state=\(state)")
        }

        let device = UIDevice.current
        batteryWasMonitored = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        device.beginGeneratingDeviceOrientationNotifications()
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { n in
                nonisolated(unsafe) let n = n   // delivered on the main queue; only read there
                MainActor.assumeIsolated { handler(n) }
            })
        }
        observe(UIScreen.brightnessDidChangeNotification) { [weak self] _ in
            self?.note("brightness \(String(format: "%.2f", Double(UIScreen.main.brightness)))")
        }
        observe(UIDevice.batteryStateDidChangeNotification) { [weak self] _ in
            self?.note("battery \(Self.batteryName(UIDevice.current.batteryState))")
        }
        observe(UIDevice.orientationDidChangeNotification) { [weak self] _ in
            self?.note("orientation \(Self.orientationName(UIDevice.current.orientation))")
        }
        observe(AVAudioSession.interruptionNotification) { [weak self] n in
            let u = n.userInfo
            let type = (u?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .began
                ? "began" : "ended"
            var text = "audio interruption \(type)"
            if let r = u?[AVAudioSessionInterruptionReasonKey] as? UInt { text += " reason=\(r)" }
            if let o = u?[AVAudioSessionInterruptionOptionKey] as? UInt { text += " options=\(o)" }
            self?.note(text)
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] n in
            let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            self?.note("audio route change reason=\(r.map(String.init) ?? "?")")
        }

        let m = CMMotionManager()
        if m.isDeviceMotionAvailable {
            m.deviceMotionUpdateInterval = 0.1
            m.startDeviceMotionUpdates(to: .main) { [weak self] d, _ in
                guard let d else { return }
                MainActor.assumeIsolated {
                    self?.peaks.feed(acceleration: (d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z),
                                     rotation: (d.rotationRate.x, d.rotationRate.y, d.rotationRate.z),
                                     gravity: (d.gravity.x, d.gravity.y, d.gravity.z))
                }
            }
            motion = m
        } else {
            note("motion unavailable")
        }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        sampler = t
    }

    func stop() {
        guard isRunning else { return }
        sampler?.invalidate(); sampler = nil
        motion?.stopDeviceMotionUpdates(); motion = nil
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        darwin.removeAll()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        UIDevice.current.isBatteryMonitoringEnabled = batteryWasMonitored
        note("=== lab stopped ===")
        try? handle?.close()
        handle = nil
        isRunning = false
    }

    func note(_ text: String) {
        guard let handle else { return }
        let line = "\(Self.timestamp.string(from: Date()))  \(text)\n"
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.synchronize()
    }

    private func sample() {
        let p = peaks.readAndReset()
        let device = UIDevice.current
        note(Self.sampleLine(lit: blanked.map { !$0 }, protectedData: UIApplication.shared.isProtectedDataAvailable,
                             app: Self.appStateName(UIApplication.shared.applicationState),
                             brightness: Double(UIScreen.main.brightness), battery: Self.batteryName(device.batteryState),
                             acceleration: p.acceleration, rotation: p.rotation, gravity: p.gravity,
                             orientation: Self.orientationName(device.orientation),
                             backgroundRemaining: UIApplication.shared.backgroundTimeRemaining))
    }

    private static func appStateName(_ s: UIApplication.State) -> String {
        switch s {
        case .active: "active"
        case .inactive: "inactive"
        default: "background"
        }
    }

    static func batteryName(_ s: UIDevice.BatteryState) -> String {
        switch s {
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        default: "unknown"
        }
    }

    static func orientationName(_ o: UIDeviceOrientation) -> String {
        switch o {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        case .faceUp: "faceUp"
        case .faceDown: "faceDown"
        default: "unknown"
        }
    }
}
