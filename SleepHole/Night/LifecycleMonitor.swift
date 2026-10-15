import CallKit
import notify
import Foundation
import SleepCore
import UIKit

/// Turns UIKit / system signals into `NightEvent`s (plan §6.2).
///
/// Only documented signals are used (Apple refused a build for listening to the undocumented lock notifications,
/// ITMS-90699, 2026-10-14):
///  * `protectedDataWillBecomeUnavailable` – the phone locked / the screen went off (arrives as fast as the old
///    Darwin lock signal, measured). It ends an open trip and tells a lock from leaving the app.
///  * `protectedDataDidBecomeAvailable` – the user was recognised (Face ID / Touch ID / passcode), on the lock screen or
///    after unlocking into another app (the two cannot be told apart). If the app is still not in front
///    `lockScreenWindow` later, the phone is being used → `.usedLockScreen`.
/// On `didEnterBackground` the monitor waits `decisionDelay` and then decides lock vs. left-app.
/// Every raw signal is also reported via `onRaw` for the F2 spike log.
@MainActor
final class LifecycleMonitor {
    var onEvent: ((NightEventKind, Date) -> Void)?
    var onRaw: ((String) -> Void)?
    /// iOS tells the running app that it is about to be terminated: swiped away in the app switcher (owner 2026-10-04,
    /// R4: that counts as leaving the app) or the phone restarts / shuts down. Called synchronously on the main
    /// thread – the process dies right after, so whatever must survive has to be saved before this returns.
    var onTerminate: (() -> Void)?

    static let decisionDelay: Duration = .seconds(3)      // lock signals arrive ~1.6 s after background (device log)

    /// After the user was recognised (protected data available) while the app is not in front, this long without a lock
    /// and without the app coming back means the phone is being used elsewhere → `.usedLockScreen` (owner 2026-10-14).
    nonisolated static let lockScreenWindow: Duration = .seconds(8)

    // Seams for tests (hosted tests always see the app as active and cannot wait 8 s per case); production defaults.
    var isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    var isProtectedDataAvailable: () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    /// Can this phone tell locking from leaving the app (passcode + Face ID / Touch ID)? When not, a background trip is
    /// never counted as leaving (the user's favour); closing the app and calls keep their rules.
    var canTellLockFromLeaving: () -> Bool = { LockCapability.canTellLockFromLeaving() }
    var screenWindow: Duration = LifecycleMonitor.lockScreenWindow
    var backgroundDelay: Duration = LifecycleMonitor.decisionDelay

    private var tokens: [NSObjectProtocol] = []
    private var lastLockSignal: Date?
    private var pendingBackground: Task<Void, Never>?
    /// The window after a recognition while the app is not in front.
    private var pendingLockUse: Task<Void, Never>?
    private var isAway = false {
        didSet { if !isAway { lockTrip = false } }
    }
    /// The open trip began as lock-screen use (`.usedLockScreen`), not as a real leave.
    private var lockTrip = false
    /// Protected data is locked, as told by the two notifications. `isProtectedDataAvailable` stays true for several
    /// seconds after a lock, so the state must come from the notifications, not from that flag.
    private var dataLocked = false
    private let callObserver = CXCallObserver()
    private var callDelegate: CallDelegate?
    private var activeCalls = Set<UUID>()
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        dataLocked = !isProtectedDataAvailable()
        let nc = NotificationCenter.default
        func observe(_ name: Notification.Name, queue: OperationQueue? = .main, _ handler: @escaping @MainActor () -> Void) {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: queue) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
        observe(UIApplication.willResignActiveNotification) { [weak self] in self?.raw("willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] in self?.didEnterBackground() }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] in self?.raw("willEnterForeground") }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] in self?.didBecomeActive() }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { [weak self] in
            self?.dataProtectionChanged(locked: true)
        }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { [weak self] in
            self?.dataProtectionChanged(locked: false)
        }
        // `queue: nil` = the block runs in place, on the posting (main) thread, before the notification returns: a hop
        // to the main queue could come too late – the process is about to die
        observe(UIApplication.willTerminateNotification, queue: nil) { [weak self] in
            self?.raw("willTerminate")
            self?.onTerminate?()
        }

        let delegate = CallDelegate { [weak self] call in self?.callChanged(call) }
        callDelegate = delegate
        callObserver.setDelegate(delegate, queue: .main)
        raw("monitor started · protectedData=\(UIApplication.shared.isProtectedDataAvailable)")
    }

    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        callObserver.setDelegate(nil, queue: nil)
        pendingBackground?.cancel(); pendingLockUse?.cancel(); pendingLockUse = nil
        isRunning = false
        raw("monitor stopped")
    }

    // MARK: - signals

    /// The two protected-data notifications. Every lock / screen-off posts "will become unavailable" at once; a wake that
    /// Face ID recognises posts "did become available" ~0.5 s after the screen comes on (sometimes twice). Only a real
    /// change of the state is reported.
    func dataProtectionChanged(locked: Bool) {
        raw(locked ? "protectedDataWillBecomeUnavailable" : "protectedDataDidBecomeAvailable")
        let changed = dataLocked != locked
        dataLocked = locked
        if changed { emit(locked ? .dataLocked : .ownerRecognised, "") }
        if locked {
            pendingLockUse?.cancel(); pendingLockUse = nil
            lockSignal("protectedData")
        } else if changed, !isAway, !isAppActive() {
            startLockUseWindow()
        }
    }

    private func lockSignal(_ source: String) {
        lastLockSignal = Date()
        if isAway {                       // left the app, then locked → away interval ends at the lock
            isAway = false
            emit(.locked, "(\(source), ends away)")
        }
    }

    /// The user was recognised while the app is not in front. If after `screenWindow` the app is still not active and
    /// no lock came in between, the phone is being used (lock-screen camera, widgets, another app) → `.usedLockScreen`,
    /// stamped at the END of the window (the window is free).
    private func startLockUseWindow() {
        pendingLockUse?.cancel()
        pendingLockUse = Task { [weak self] in
            try? await Task.sleep(for: self?.screenWindow ?? Self.lockScreenWindow)
            guard let self, !Task.isCancelled else { return }
            self.pendingLockUse = nil
            let active = self.isAppActive()
            self.raw("recognised \(Int(Self.lockScreenWindow.components.seconds))s ago · active=\(active) · locked=\(self.dataLocked)")
            if !active, !self.dataLocked, !self.isAway {
                self.isAway = true; self.lockTrip = true
                self.emit(.usedLockScreen, "(recognised and not back in time)")
            }
        }
    }

    func didEnterBackground() {
        let now = Date()
        let brightness = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.brightness }.first ?? -1
        raw(String(format: "didEnterBackground · protectedData=%@ · brightness=%.2f · calls=%d",
                   UIApplication.shared.isProtectedDataAvailable ? "yes" : "no", brightness, activeCalls.count))
        pendingBackground?.cancel()
        pendingBackground = Task { [weak self] in
            try? await Task.sleep(for: self?.backgroundDelay ?? Self.decisionDelay)
            guard let self, !Task.isCancelled else { return }
            self.pendingBackground = nil
            if let lock = self.lastLockSignal, abs(lock.timeIntervalSince(now)) < 2.5 {
                self.emit(.locked, "(background by lock)", at: now)
            } else if !self.isAppActive(), !self.isAway || self.lockTrip {
                // One trip, one `.leftApp` (B29): a real leave that is already open needs nothing more. An open
                // lock-screen trip is not a real leave, so a background that follows it still reports one.
                guard self.canTellLockFromLeaving() else {
                    // no passcode / no Face ID or Touch ID: a lock looks exactly like leaving → the user's favour
                    self.raw("(background not counted: this phone cannot tell a lock from leaving)")
                    return
                }
                self.isAway = true; self.lockTrip = false
                self.emit(.leftApp, "(background without a lock signal)", at: now)
            }
        }
    }

    private func didBecomeActive() {
        raw("didBecomeActive")
        pendingLockUse?.cancel(); pendingLockUse = nil
        if pendingBackground != nil {     // came back before the decision → nothing happened
            pendingBackground?.cancel(); pendingBackground = nil
            raw("(short background ignored)")
            return
        }
        isAway = false
        emit(.returned, "")
    }

    func callChanged(_ call: CallInfo) {
        raw("call \(call.uuid.uuidString.prefix(4)) outgoing=\(call.isOutgoing) connected=\(call.hasConnected) ended=\(call.hasEnded)")
        if call.hasEnded {
            if activeCalls.remove(call.uuid) != nil, activeCalls.isEmpty { emit(.callEnded, "") }
        } else if activeCalls.insert(call.uuid).inserted, activeCalls.count == 1 {
            emit(.callStarted, "")
        }
    }

    // MARK: - output

    private func raw(_ text: String) { onRaw?(text) }

    private func emit(_ kind: NightEventKind, _ note: String, at date: Date = Date()) {
        onRaw?("→ \(kind.rawValue) \(note)")
        onEvent?(kind, date)
    }
}

struct CallInfo: Sendable {
    let uuid: UUID, isOutgoing: Bool, hasConnected: Bool, hasEnded: Bool
}

private final class CallDelegate: NSObject, CXCallObserverDelegate, @unchecked Sendable {
    let handler: @MainActor (CallInfo) -> Void
    init(_ handler: @escaping @MainActor (CallInfo) -> Void) { self.handler = handler }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let info = CallInfo(uuid: call.uuid, isOutgoing: call.isOutgoing,
                            hasConnected: call.hasConnected, hasEnded: call.hasEnded)
        let handler = self.handler
        MainActor.assumeIsolated { handler(info) }
    }
}

/// Darwin notify center via `notify_register_dispatch` (gives access to the notification's state).
@MainActor
final class DarwinNotifications {
    static let shared = DarwinNotifications()
    private var tokens: [Int32] = []

    func observe(_ names: [String], handler: @escaping @MainActor (String, UInt64) -> Void) {
        removeAll()
        for name in names {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { token in
                var state: UInt64 = 0
                notify_get_state(token, &state)
                MainActor.assumeIsolated { handler(name, state) }
            }
            if status == NOTIFY_STATUS_OK { tokens.append(token) }
        }
    }

    /// The current state of a Darwin notification (0 when nobody has posted one yet), read without observing it.
    static func currentState(of name: String) -> UInt64 {
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return 0 }
        defer { notify_cancel(token) }
        var state: UInt64 = 0
        notify_get_state(token, &state)
        return state
    }

    func removeAll() {
        tokens.forEach { notify_cancel($0) }
        tokens.removeAll()
    }
}
